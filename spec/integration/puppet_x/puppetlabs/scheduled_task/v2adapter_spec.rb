
#!/usr/bin/env ruby
require 'spec_helper'

require 'puppet_x/puppetlabs/scheduled_task/v2adapter'

RSpec::Matchers.define :be_same_as_powershell_command do |ps_cmd|
  define_method :run_ps do |cmd|
    full_cmd = "powershell.exe -NoLogo -NoProfile -NonInteractive -Command \"#{cmd}\""

    result = `#{full_cmd}`

    result.strip
  end

  match do |actual|
    from_ps = run_ps(ps_cmd)
    actual.to_s == from_ps
  end

  failure_message do |actual|
    "expected that #{actual} would match #{run_ps(ps_cmd)} from PowerShell command #{ps_cmd}"
  end
end

def triggers
  now = Time.now

  defaults = {
    'end_day'                 => 0,
    'end_year'                => 0,
    'minutes_interval'        => 0,
    'end_month'               => 0,
    'minutes_duration'        => 0,
    'start_year'              => now.year,
    'start_month'             => now.month,
    'start_day'               => now.day,
    'start_hour'              => now.hour,
    'start_minute'            => now.min,
  }

  [
    # dummy time trigger
    defaults.merge({
      'trigger_type'            => :TASK_TIME_TRIGGER_ONCE,
    }),
    defaults.merge({
      'type'                    => { 'days_interval' => 1 },
      'trigger_type'            => :TASK_TIME_TRIGGER_DAILY,
    }),
    defaults.merge({
      'type'         => {
        'weeks_interval' => 1,
        'days_of_week'   => PuppetX::PuppetLabs::ScheduledTask::Trigger::V1::Day::TASK_MONDAY,
      },
      'trigger_type'            => :TASK_TIME_TRIGGER_WEEKLY,
    }),
    defaults.merge({
      'type'         => {
        'months' => PuppetX::PuppetLabs::ScheduledTask::Trigger::V1::Month::TASK_JANUARY,
        # Bitwise mask, reference on MSDN:
        # https://msdn.microsoft.com/en-us/library/windows/desktop/aa380735(v=vs.85).aspx
        # 8192 is for the 14th
        'days'   => 8192,
      },
      'trigger_type'            => :TASK_TIME_TRIGGER_MONTHLYDATE,
    }),
    defaults.merge({
      'type'         => {
        'months'       => PuppetX::PuppetLabs::ScheduledTask::Trigger::V1::Month::TASK_JANUARY,
        'weeks'        => PuppetX::PuppetLabs::ScheduledTask::Trigger::V1::Occurrence::TASK_FIRST_WEEK,
        'days_of_week' => PuppetX::PuppetLabs::ScheduledTask::Trigger::V1::Day::TASK_MONDAY,
      },
      'trigger_type'            => :TASK_TIME_TRIGGER_MONTHLYDOW,
    })
  ]
end

# These integration tests use V2 API tasks and make sure they save
# and read back correctly
describe "PuppetX::PuppetLabs::ScheduledTask::V2Adapter", :if => Puppet.features.microsoft_windows? do
  subject = PuppetX::PuppetLabs::ScheduledTask::V2Adapter

  context "should be able to create trigger" do
    before(:all) do
      @task_name = 'puppet_task_' + SecureRandom.uuid.to_s

      task = subject.new(@task_name)
      task.application_name = 'cmd.exe'
      task.parameters = '/c exit 0'
      task.save
    end

    after(:all) do
      subject.delete(@task_name) if subject.exists?(@task_name)
    end

    it "and return the same application_name and properties as those originally set" do
      expect(subject).to be_exists(@task_name)

      task = subject.new(@task_name)
      # verify initial task configuration
      expect(task.parameters).to eq('/c exit 0')
      expect(task.application_name).to eq('cmd.exe')
    end

    triggers.each do |trigger|
      after(:each) do
        task = subject.new(@task_name)
        1.upto(task.trigger_count).each { |i| task.delete_trigger(0) }
        task.save
      end

      it "#{trigger['trigger_type']} and return the same properties as those set" do
        # verifying task exists guarantees that .new below loads existing task
        expect(subject).to be_exists(@task_name)

        # append the trigger of given type
        task = subject.new(@task_name)
        task.append_trigger(trigger)
        task.save

        # reload a new task object by name
        task = subject.new(@task_name)

        # trigger specific validation
        expect(task.trigger_count).to eq(1)
        expect(task.trigger(0)['trigger_type']).to eq(trigger['trigger_type'])
        expect(task.trigger(0)['type']).to eq(trigger['type']) if trigger['type']
      end
    end
  end

  context "When managing a task" do
    before(:each) do
      @task_name = 'puppet_task_' + SecureRandom.uuid.to_s
      task = subject.new(@task_name)
      task.append_trigger(triggers[0])
      task.application_name = 'cmd.exe'
      task.parameters = '/c exit 0'
      task.save
    end

    after(:each) do
      subject.delete(@task_name) if subject.exists?(@task_name)
    end

    it 'should be able to determine if the task exists or not' do
      bad_task_name = SecureRandom.uuid.to_s
      expect(subject.exists?(@task_name)).to be(true)
      expect(subject.exists?(bad_task_name)).to be(false)
    end

    it 'should able to update a trigger' do
      new_trigger = triggers[0].merge({
        'start_year'              => 2112,
        'start_month'             => 12,
        'start_day'               => 12,
      })

      task = subject.new(@task_name)
      expect(task.delete_trigger(0)).to be(1)
      task.append_trigger(new_trigger)
      task.save
      ps_cmd = '([string]((Get-ScheduledTask | ? { $_.TaskName -eq \'' + @task_name + '\' }).Triggers.StartBoundary) -split \'T\')[0]'
      expect('2112-12-12').to be_same_as_powershell_command(ps_cmd)
    end

    it 'should be able to update a command' do
      new_application_name = 'notepad.exe'
      ps_cmd = '[string]((Get-ScheduledTask | ? { $_.TaskName -eq \'' + @task_name + '\' }).Actions[0].Execute)'
      task = subject.new(@task_name)

      expect('cmd.exe').to be_same_as_powershell_command(ps_cmd)
      task.application_name = new_application_name
      task.save
      expect(new_application_name).to be_same_as_powershell_command(ps_cmd)
    end

    it 'should be able to update command parameters' do
      new_parameters = '/nonsense /utter /nonsense'
      ps_cmd = '[string]((Get-ScheduledTask | ? { $_.TaskName -eq \'' + @task_name + '\' }).Actions[0].Arguments)'
      task = subject.new(@task_name)

      expect('/c exit 0').to be_same_as_powershell_command(ps_cmd)
      task.parameters = new_parameters
      task.save
      expect(new_parameters).to be_same_as_powershell_command(ps_cmd)
    end

    it 'should be able to update the working directory' do
      new_working_directory = 'C:\Somewhere'
      ps_cmd = '[string]((Get-ScheduledTask | ? { $_.TaskName -eq \'' + @task_name + '\' }).Actions[0].WorkingDirectory)'
      task = subject.new(@task_name)

      expect('').to be_same_as_powershell_command(ps_cmd)
      task.working_directory = new_working_directory
      task.save
      expect(new_working_directory).to be_same_as_powershell_command(ps_cmd)
    end
  end
end