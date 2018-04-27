#!/usr/bin/env ruby
require 'spec_helper'
require 'puppet_x/puppetlabs/scheduled_task/trigger'

describe PuppetX::PuppetLabs::ScheduledTask::Trigger do
  describe "#string_to_int" do
    [nil, ''].each do |value|
      it "should return 0 given value '#{value}' (#{value.class})" do
        expect(subject.string_to_int(value)).to be_zero
      end
    end

    [
      { :input => 0, :expected => 0 },
      { :input => 1.2, :expected => 1.2} ,
      { :input => 100, :expected => 100 }
    ].each do |value|
      it "should coerce numeric input #{value[:input]} to #{value[:expected]}" do
        expect(subject.string_to_int(value[:input])).to eq(value[:expected])
      end
    end

    [:foo, [], {}].each do |value|
      it "should raise ArgumentError given value '#{value}' (#{value.class})" do
        expect { subject.string_to_int(value) }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#string_to_date" do
    [nil, ''].each do |value|
      it "should return nil given value '#{value}' (#{value.class})" do
        expect(subject.string_to_date(value)).to eq(nil)
      end
    end

    [
      { :input => '2018-01-02T03:04:05', :expected => DateTime.new(2018, 1, 2, 3, 4, 5) },
      { :input => '1899-12-30T00:00:00', :expected => DateTime.new(1899, 12, 30, 0, 0, 0) },
    ].each do |value|
      it "should return a valid DateTime object for date string #{value[:input]}" do
        expect(subject.string_to_date(value[:input])).to eq(value[:expected])
      end
    end

    [:foo, [], {}].each do |value|
      it "should raise ArgumentError given value '#{value}' (#{value.class})" do
        expect { subject.string_to_date(value) }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#iso8601_datetime" do
    [
      # year, month, day, hour, minute
      { :input => [2018, 3, 20, 8, 57], :expected => '2018-03-20T08:57:00' },
      { :input => [1899, 12, 30, 0, 0], :expected => '1899-12-30T00:00:00' },
    ].each do |value|
      it "should return formatted date string #{value[:expected]} for date components #{value[:input]}" do
        # The timestring returned is localized so the UTC offset will vary between systems
        expect(subject.iso8601_datetime(*value[:input])).to match(/#{value[:expected]}(-|\+)\d{2}:\d{2}/)
      end
    end
  end
end

describe PuppetX::PuppetLabs::ScheduledTask::Trigger::V1 do
  describe '#normalized_date' do
    it 'should format the date without leading zeros' do
      expect(subject.class.normalized_date(2011, 01, 01)).to eq('2011-1-1')
    end
  end

  describe '#normalized_time' do
    it 'should format the time as {24h}:{minutes}' do
      expect(subject.class.normalized_time(8, 37)).to eq('08:37')
    end

    it 'should format the time as {24h}:{minutes}' do
      expect(subject.class.normalized_time(20, 0)).to eq('20:00')
    end
  end

  describe "#canonicalize_and_validate" do
    [
      {
        :input =>
        {
          'END_day' => nil,
          'end_Month' => nil,
          'End_year' => nil,
          'FLAGS' => nil,
          'minutes_duration' => nil,
          'MINutes_intERVAL' => nil,
          'Start_day' => nil,
          'START_hour' => nil,
          'start_Minute' => nil,
          'start_YEAR' => nil,
          'Trigger_Type' => nil,
          'TyPe' =>
          {
            'days_Interval' => nil,
            'Weeks_interval' => nil,
            'DAYS_of_Week' => nil,
            'MONTHS' => nil,
            'daYS' => nil,
            'weeks' => nil
          }
        },
        # all keys are lower
        :expected =>
        {
          'end_day' => nil,
          'end_month' => nil,
          'end_year' => nil,
          'flags' => nil,
          'minutes_duration' => nil,
          'minutes_interval' => nil,
          'start_day' => nil,
          'start_hour' => nil,
          'start_minute' => nil,
          'start_year' => nil,
          'trigger_type' => nil,
          'type' =>
          {
            'days_interval' => nil,
            'weeks_interval' => nil,
            'days_of_week' => nil,
            'months' => nil,
            'days' => nil,
            'weeks' => nil
          }
        }
      },
      {
        :input => { 'type' => { 'DAYS_Interval' => nil, } },
        :expected => { 'type' => { 'days_interval' => nil, } },
      },
    ].each do |value|
      it "should return downcased keys #{value[:expected]} given a hash with valid case-insensitive keys #{value[:input]}" do
        expect(subject.class.canonicalize_and_validate(value[:input])).to eq(value[:expected])
      end
    end

    [
      { :foo => nil, 'type' => {} },
      { :type => nil },
      { [] => nil },
      { 'type' => [] },
      { 'type' => 1 },
    ].each do |value|
      it "should fail with ArgumentError given a hash with invalid keys #{value}" do
        expect { subject.class.canonicalize_and_validate(value) }.to raise_error(ArgumentError)
      end
    end
  end

end

describe PuppetX::PuppetLabs::ScheduledTask::Trigger::Duration do
  DAYS_IN_YEAR = 365.2422
  SECONDS_IN_HOUR = 60 * 60
  SECONDS_IN_DAY = 24 * SECONDS_IN_HOUR

  EXPECTED_CONVERSIONS =
  [
    {
      :duration => 'P1M4DT2H5M',
      :duration_hash => {
        :year => nil,
        :month => "1",
        :day => "4",
        :minute => "5",
        :hour => "2",
        :second => nil,
      },
      :expected_seconds => (DAYS_IN_YEAR / 12 * SECONDS_IN_DAY) + (4 * SECONDS_IN_DAY) + (5 * 60) + (2 * SECONDS_IN_HOUR),
    },
    {
      :duration => 'PT20M',
      :duration_hash => {
        :year => nil,
        :month => nil,
        :day => nil,
        :minute => "20",
        :hour => nil,
        :second => nil,
      },
      :expected_seconds => 20 * 60
    },
    {
      :duration => 'P1Y2M30DT12H60M60S',
      :duration_hash => {
        :year => "1",
        :month => "2",
        :day => "30",
        :minute => "60",
        :hour => "12",
        :second => "60",
      },
      :expected_seconds => (DAYS_IN_YEAR * SECONDS_IN_DAY) + ((DAYS_IN_YEAR / 12 * 2) * SECONDS_IN_DAY) + (30 * SECONDS_IN_DAY) + (60 * 60) + (SECONDS_IN_HOUR * 12) + 60
    },
  ].freeze

  describe '#to_hash' do
    EXPECTED_CONVERSIONS.each do |conversion|
      it "should create expected hashes from duration string #{conversion[:duration]}" do
        expect(subject.class.to_hash(conversion[:duration])).to eq(conversion[:duration_hash])
      end
    end

    [
      'ABC',
      '123'
    ]
    .each do |duration|
      it "should return nil when failing to parse duration string #{duration}" do
        expect(subject.class.to_hash(duration)).to be_nil
      end
    end
  end

  describe '#hash_to_seconds' do
    it "should return 0 for a nil value" do
      expect(subject.class.hash_to_seconds(nil)).to be_zero
    end

    EXPECTED_CONVERSIONS.each do |conversion|
      rounded_seconds = conversion[:expected_seconds].to_i
      it "should return #{rounded_seconds} seconds given a duration hash" do
        converted = subject.class.hash_to_seconds(conversion[:duration_hash])
        expect(converted).to eq(rounded_seconds)
      end
    end
  end

  describe '#to_minutes' do
    it "should return 0 for a nil value" do
      expect(subject.class.to_minutes(nil)).to be_zero
    end

    it "should return 0 for an empty string value" do
      expect(subject.class.to_minutes('')).to be_zero
    end

    [1234, '0', 999.999].each do |value|
      it "should return 0 for the #{value.class} value: #{value}" do
        expect(subject.class.to_minutes(value)).to be_zero
      end
    end

    EXPECTED_CONVERSIONS.each do |conversion|
      expected_minutes = conversion[:expected_seconds].to_i / 60
      it "should return #{expected_minutes} minutes given a duration #{conversion[:duration]}" do
        converted = subject.class.to_minutes(conversion[:duration])
        expect(converted).to eq(expected_minutes)
      end
    end
  end
end

describe PuppetX::PuppetLabs::ScheduledTask::Trigger::V1::Day do
  EXPECTED_DAY_CONVERSIONS =
  [
    { :days => 'sun', :bitmask => 0b1 },
    { :days => [], :bitmask => 0 },
    { :days => ['mon'], :bitmask => 0b10 },
    { :days => ['sun', 'sat'], :bitmask => 0b1000001  },
    {
      :days => ['sun', 'mon', 'tues', 'wed', 'thurs', 'fri', 'sat'],
      :bitmask => 0b1111111
    },
  ].freeze

  describe '#names_to_bitmask' do
    EXPECTED_DAY_CONVERSIONS.each do |conversion|
      it "should create expected bitmask #{'%08b' % conversion[:bitmask]} from days #{conversion[:days]}" do
        expect(subject.class.names_to_bitmask(conversion[:days])).to eq(conversion[:bitmask])
      end
    end

    [ nil, 1, {}, 'foo', ['bar'] ].each do |value|
      it "should raise an error with invalid value: #{value}" do
        expect { subject.class.names_to_bitmask(value) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#bitmask_to_names' do
    EXPECTED_DAY_CONVERSIONS.each do |conversion|
      it "should create expected days #{conversion[:days]} from bitmask #{'%08b' % conversion[:bitmask]}" do
        expect(subject.class.bitmask_to_names(conversion[:bitmask])).to eq([conversion[:days]].flatten)
      end
    end

    [ nil, {}, ['bar'] ].each do |value|
      it "should raise an error with invalid value: #{value}" do
        expect { subject.class.bitmask_to_names(value) }.to raise_error(TypeError)
      end
    end

    [ -1, 'foo', 0b1111111 + 1 ].each do |value|
      it "should raise an error with invalid value: #{value}" do
        expect { subject.class.bitmask_to_names(value) }.to raise_error(ArgumentError)
      end
    end
  end
end

describe PuppetX::PuppetLabs::ScheduledTask::Trigger::V1::Days do
  EXPECTED_DAYS_CONVERSIONS =
  [
    { :days => 1,                       :bitmask => 0b00000000000000000000000000000001 },
    { :days => [],                      :bitmask => 0 },
    { :days => [2],                     :bitmask => 0b00000000000000000000000000000010 },
    { :days => [3, 5, 8, 12],           :bitmask => 0b00000000000000000000100010010100 },
    { :days => [3, 5, 8, 12, 'last'],   :bitmask => 0b10000000000000000000100010010100 },
    { :days => (1..31).to_a,            :bitmask => 0b01111111111111111111111111111111 },
    { :days => (1..31).to_a + ['last'], :bitmask => 0b11111111111111111111111111111111 },
    # equivalent representations
    { :days => 'last',                  :bitmask => 0b10000000000000000000000000000000 },
    { :days => ['last'],                :bitmask => 1 << (32-1) },
    { :days => [1, 'last'],             :bitmask => 0b10000000000000000000000000000001 },
    { :days => [1, 30, 31, 'last'],     :bitmask => 0b11100000000000000000000000000001 },
  ].freeze

  describe '#indexes_to_bitmask' do
    EXPECTED_DAYS_CONVERSIONS.each do |conversion|
      it "should create expected bitmask #{'%32b' % conversion[:bitmask]} from days #{conversion[:days]}" do
        expect(subject.class.indexes_to_bitmask(conversion[:days])).to eq(conversion[:bitmask])
      end
    end

    [ nil, {} ].each do |value|
      it "should raise a TypeError with value: #{value}" do
        expect { subject.class.indexes_to_bitmask(value) }.to raise_error(TypeError)
      end
    end

    [ 'foo', ['bar'], -1, 0x1000, [33] ].each do |value|
      it "should raise an ArgumentError with value: #{value}" do
        expect { subject.class.indexes_to_bitmask(value) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#bitmask_to_indexes' do
    EXPECTED_DAYS_CONVERSIONS.each do |conversion|
      it "should create expected days #{conversion[:days]} from bitmask #{'%32b' % conversion[:bitmask]}" do
        expect(subject.class.bitmask_to_indexes(conversion[:bitmask])).to eq([conversion[:days]].flatten)
      end
    end

    [ nil, {}, ['bar'] ].each do |value|
      it "should raise a TypeError with value: #{value}" do
        expect { subject.class.bitmask_to_indexes(value) }.to raise_error(TypeError)
      end
    end

    [ 'foo', -1, 0b11111111111111111111111111111111 + 1 ].each do |value|
      it "should raise an ArgumentError with value: #{value}" do
        expect { subject.class.bitmask_to_indexes(value) }.to raise_error(ArgumentError)
      end
    end
  end
end
describe PuppetX::PuppetLabs::ScheduledTask::Trigger::V1::Month do
  EXPECTED_MONTH_CONVERSIONS =
  [
    { :months => 1,            :bitmask => 0b000000000001 },
    { :months => [1],          :bitmask => 0b000000000001 },
    { :months => [],           :bitmask => 0 },
    { :months => [1, 2],       :bitmask => 0b000000000011 },
    { :months => [1, 12],      :bitmask => 0b100000000001 },
    { :months => (1..12).to_a, :bitmask => 0b111111111111 },
  ].freeze

  describe '#indexes_to_bitmask' do
    EXPECTED_MONTH_CONVERSIONS.each do |conversion|
      it "should create expected bitmask #{'%12b' % conversion[:bitmask]} from months #{conversion[:months]}" do
        expect(subject.class.indexes_to_bitmask(conversion[:months])).to eq(conversion[:bitmask])
      end
    end

    [ nil, 13, [13], {}, 'foo', ['bar'] ].each do |value|
      it "should raise an error with invalid value: #{value}" do
        expect { subject.class.indexes_to_bitmask(value) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#bitmask_to_indexes' do
    EXPECTED_MONTH_CONVERSIONS.each do |conversion|
      it "should create expected months #{conversion[:months]} from bitmask #{'%08b' % conversion[:bitmask]}" do
        expect(subject.class.bitmask_to_indexes(conversion[:bitmask])).to eq([conversion[:months]].flatten)
      end
    end
  end

  [ nil, [13], {}, ['bar'] ].each do |value|
    it "should raise a TypeError with value: #{value}" do
      expect { subject.class.bitmask_to_indexes(value) }.to raise_error(TypeError)
    end
  end

  [ 'foo', -1, 0b111111111111 + 1 ].each do |value|
    it "should raise an ArgumentError with value: #{value}" do
      expect { subject.class.bitmask_to_indexes(value) }.to raise_error(ArgumentError)
    end
  end
end
