
require 'tzinfo'


module EtOrbi

  VERSION = '1.0.0'

  class EoTime

    attr_reader :seconds
    attr_reader :zone

    def initialize(s, zone)

      @seconds = s.to_f
      @zone = self.class.get_tzone(zone || :current)

      fail ArgumentError.new(
        "cannot determine timezone from #{zone.inspect}" +
        " (etz:#{ENV['TZ'].inspect},tnz:#{Time.now.zone.inspect}," +
        "tzid:#{defined?(TZInfo::Data).inspect}," +
        "rv:#{RUBY_VERSION.inspect},rp:#{RUBY_PLATFORM.inspect}," +
        "stz:(#{self.class.gather_tzs.map { |k, v| "#{k}:#{v.inspect}"}.join(',')})) \n" +
        "Try setting `ENV['TZ'] = 'Continent/City'` in your script " +
        "(see https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)" +
        (defined?(TZInfo::Data) ? '' : " and adding 'tzinfo-data' to your gems")
      ) unless @zone

      @time = nil # cache for #to_time result
    end

    def seconds=(f)

      @time = nil
      @seconds = f
    end

    def zone=(z)

      @time = nil
      @zone = self.class.get_tzone(zone || :current)
    end

    def utc

      Time.utc(1970, 1, 1) + @seconds
    end

    # Returns a Ruby Time instance.
    #
    # Warning: the timezone of that Time instance will be UTC.
    #
    def to_time

      @time ||= begin; u = utc; @zone.period_for_utc(u).to_local(u); end
    end

    %w[
      year month day wday hour min sec usec asctime
    ].each do |m|
      define_method(m) { to_time.send(m) }
    end
    def iso8601(fraction_digits=0); to_time.iso8601(fraction_digits); end

    def ==(o)

      o.is_a?(EoTime) && o.seconds == @seconds && o.zone == @zone
    end
    #alias eq? == # FIXME see Object#== (ri)

    def >(o); @seconds > _to_f(o); end
    def >=(o); @seconds >= _to_f(o); end
    def <(o); @seconds < _to_f(o); end
    def <=(o); @seconds <= _to_f(o); end
    def <=>(o); @seconds <=> _to_f(o); end

    alias getutc utc
    alias getgm utc

    def to_i

      @seconds.to_i
    end

    def to_f

      @seconds
    end

    def is_dst?

      @zone.period_for_utc(utc).std_offset != 0
    end
    alias isdst is_dst?

    def utc_offset

      #@zone.period_for_utc(utc).utc_offset
      #@zone.period_for_utc(utc).utc_total_offset
      #@zone.period_for_utc(utc).std_offset
      @zone.period_for_utc(utc).utc_offset
    end

    def strftime(format)

      format = format.gsub(/%(\/?Z|:{0,2}z)/) { |f| strfz(f) }

      to_time.strftime(format)
    end

    def add(t); @time = nil; @seconds += t.to_f; end
    def subtract(t); @time = nil; @seconds -= t.to_f; end

    def +(t); inc(t, 1); end
    def -(t); inc(t, -1); end

    WEEK_S = 7 * 24 * 3600

    def monthdays

      date = to_time

      pos = 1
      d = self.dup

      loop do
        d.add(-WEEK_S)
        break if d.month != date.month
        pos = pos + 1
      end

      neg = -1
      d = self.dup

      loop do
        d.add(WEEK_S)
        break if d.month != date.month
        neg = neg - 1
      end

      [ "#{date.wday}##{pos}", "#{date.wday}##{neg}" ]
    end

    def to_s

      strftime('%Y-%m-%d %H:%M:%S %z')
    end

    def to_debug_s

      uo = self.utc_offset
      uos = uo < 0 ? '-' : '+'
      uo = uo.abs
      uoh, uom = [ uo / 3600, uo % 3600 ]

      [
        'zt',
        self.strftime('%Y-%m-%d %H:%M:%S'),
        "%s%02d:%02d" % [ uos, uoh, uom ],
        "dst:#{self.isdst}"
      ].join(' ')
    end

    # Debug current time by showing local time / delta / utc time
    # for example: "0120-7(0820)"
    #
    def to_utc_comparison_s

      per = @zone.period_for_utc(utc)
      off = per.utc_total_offset

      off = off / 3600
      off = off >= 0 ? "+#{off}" : off.to_s

      strftime('%H%M') + off + utc.strftime('(%H%M)')
    end

    def to_time_s

      strftime("%H:%M:%S.#{'%06d' % usec}")
    end

    def self.now(zone=nil)

      EoTime.new(Time.now.to_f, zone)
    end

    # https://en.wikipedia.org/wiki/ISO_8601
    # Postel's law applies
    #
    def self.extract_iso8601_zone(s)

      m = s.match(
        /[0-2]\d(?::?[0-6]\d(?::?[0-6]\d))?\s*([+-]\d\d(?::?\d\d)?)\s*\z/)
      return nil unless m

      zs = m[1].split(':')
      zs << '00' if zs.length < 2

      zh = zs[0].to_i.abs

      return nil if zh > 24
      return nil if zh == 24 && zs[1].to_i != 0

      zs.join(':')
    end

    def self.parse(str, opts={})

      if defined?(::Chronic) && t = ::Chronic.parse(str, opts)
        return EoTime.new(t, nil)
      end

      #rold = RUBY_VERSION < '1.9.0'
      #rold = RUBY_VERSION < '2.0.0'

      begin
        DateTime.parse(str)
      rescue
        fail ArgumentError, "no time information in #{str.inspect}"
      end #if rold
        #
        # is necessary since Time.parse('xxx') in Ruby < 1.9 yields `now`

      zone = nil

      s =
        str.gsub(/\S+/) do |w|
          if z = get_tzone(w)
            zone ||= z
            ''
          else
            w
          end
        end

      local = Time.parse(s)
      izone = extract_iso8601_zone(s)

      zone ||=
        if s.match(/\dZ\b/)
          get_tzone('Zulu')
        #elsif rold && izone
        elsif izone
          get_tzone(izone)
        elsif local.zone.nil? && izone
          get_tzone(local.strftime('%:z'))
        else
          get_tzone(:local)
        end

      secs =
        #if rold && izone
        if izone
          local.to_f
        else
          zone.period_for_local(local).to_utc(local).to_f
        end

      EoTime.new(secs, zone)
    end

    def self.get_tzone(str)

      return str if str.is_a?(::TZInfo::Timezone)

      # discard quickly when it's certainly not a timezone

      return nil if str == nil
      return nil if str == '*'

      ostr = str
      str = :current if str == :local

      # use Rails' zone by default if Rails is present

      return Time.zone.tzinfo if (
        ENV['TZ'].nil? && str == :current &&
        Time.respond_to?(:zone) && Time.zone.respond_to?(:tzinfo)
      )

      # ok, it's a timezone then

      str = ENV['TZ'] || Time.now.zone if str == :current

      # utc_offset

      if str.is_a?(Numeric)
        i = str.to_i
        sn = i < 0 ? '-' : '+'; i = i.abs
        hr = i / 3600; mn = i % 3600; sc = i % 60
        str = (sc > 0 ? "%s%02d:%02d:%02d" : "%s%02d:%02d") % [ sn, hr, mn, sc ]
      end

      return nil if str.index('#')
        # counters "sun#2", etc... On OSX would go all the way to true

      # vanilla time zones

      z = (::TZInfo::Timezone.get(str) rescue nil)
      return z if z

      # time zone abbreviations

      if str.match(/\A[A-Z0-9-]{3,6}\z/)

        toff = Time.now.utc_offset
        toff = nil if str != Time.now.zone

        twin = Time.utc(Time.now.year, 1, 1) # winter
        tsum = Time.utc(Time.now.year, 7, 1) # summer

        z =
          ::TZInfo::Timezone.all.find do |tz|

            pwin = tz.period_for_utc(twin)
            psum = tz.period_for_utc(tsum)

            if toff
              (pwin.abbreviation.to_s == str && pwin.utc_offset == toff) ||
              (psum.abbreviation.to_s == str && psum.utc_offset == toff)
            else
              # returns the first tz with the given abbreviation, almost useless
              # favour fully named zones...
              pwin.abbreviation.to_s == str ||
              psum.abbreviation.to_s == str
            end
          end
        return z if z
      end

      # some time zone aliases

      return ::TZInfo::Timezone.get('Zulu') if %w[ Z ].include?(str)

      # custom timezones, no DST, just an offset, like "+08:00" or "-01:30"

      tz = (@custom_tz_cache ||= {})[str]
      return tz if tz

      if m = str.match(/\A([+-][0-1][0-9]):?([0-5][0-9])\z/)

        hr = m[1].to_i
        mn = m[2].to_i

        hr = nil if hr.abs > 11
        hr = nil if mn > 59
        mn = -mn if hr && hr < 0

        return (
          @custom_tz_cache[str] =
            begin
              tzi = TZInfo::TransitionDataTimezoneInfo.new(str)
              tzi.offset(str, hr * 3600 + mn * 60, 0, str)
              tzi.create_timezone
            end
        ) if hr
      end

      # try with ENV['TZ']

      z = ostr == :current && (::TZInfo::Timezone.get(ENV['TZ']) rescue nil)
      return z if z

      # ask the system

      z = ostr == :current && (::TZInfo::Timezone.get(find_tz) rescue nil)
      return z if z

      # so it's not a timezone.

      nil
    end

    def self.debian_tz

      path = '/etc/timezone'

      File.exist?(path) ? File.read(path).strip : nil
    rescue; nil; end

    def self.centos_tz

      path = '/etc/sysconfig/clock'

      File.open(path, 'rb') do |f|
        until f.eof?
          if m = f.readline.match(/ZONE="([^"]+)"/); return m[1]; end
        end
      end if File.exist?(path)

      nil
    rescue; nil; end

    def self.osx_tz

      path = '/etc/localtime'

      File.symlink?(path) ?
        File.readlink(path).split('/')[4..-1].join('/') :
        nil
    rescue; nil; end

    def self.find_tz

      debian_tz || centos_tz || osx_tz
    end

    def self.gather_tzs

      { :debian => debian_tz, :centos => centos_tz, :osx => osx_tz }
    end

    def self.local_tzone

      get_tzone(:local)
    end

    def self.make(o)

      zt =
        case o
          when Time
            EoTime.new(o.to_f, o.zone)
          when Date
            t =
              o.respond_to?(:to_time) ?
              o.to_time :
              Time.parse(o.strftime('%Y-%m-%d %H:%M:%S'))
            EoTime.new(t.to_f, t.zone)
          when String
            #Rufus::Scheduler.parse_in(o, :no_error => true) || self.parse(o)
            self.parse(o)
          else
            o
        end

      zt = EoTime.new(Time.now.to_f + zt, nil) if zt.is_a?(Numeric)

      fail ArgumentError.new(
        "cannot turn #{o.inspect} to a EoTime instance"
      ) unless zt.is_a?(EoTime)

      zt
    end

    #def in_zone(&block)
    #
    #  current_timezone = ENV['TZ']
    #  ENV['TZ'] = @zone
    #
    #  block.call
    #
    #ensure
    #
    #  ENV['TZ'] = current_timezone
    #end
      #
      # kept around as a (thread-unsafe) relic

    def self.list_tzones(time)

      tu = time.dup.utc # ! dup because #utc changes the tz of the Time instance
      tzo = time.zone

      twin = Time.utc(time.year, 1, 1) # winter
      tsum = Time.utc(time.year, 7, 1) # summer

      ::TZInfo::Timezone.all.select do |tz|

        pwin = tz.period_for_utc(twin)
        psum = tz.period_for_utc(tsum)
        awin = pwin.abbreviation.to_s
        asum = psum.abbreviation.to_s

        next false \
          unless awin == tzo || asum == tzo

        time1 = tz.period_for_utc(tu).to_local(tu)

        time.strftime('%M%H%d%m%Y') == time1.strftime('%M%H%d%m%Y')
      end
    end

    def self.determine_tzone(time)

      tzs = list_tzones(time)

      tzname = ENV['TZ']
      if tz = tzname && tzs.find { |z| z.name == tzname }; return tz; end

      tzs.first
    end

    protected

    def inc(t, dir)

      if t.is_a?(Numeric)
        nt = self.dup
        nt.seconds += dir * t.to_f
        nt
      elsif t.respond_to?(:to_f)
        @seconds + dir * t.to_f
      else
        fail ArgumentError.new(
          "cannot call EoTime #- or #+ with arg of class #{t.class}")
      end
    end

    def _to_f(o)

      fail ArgumentError(
        "comparison of EoTime with #{o.inspect} failed"
      ) unless o.is_a?(EoTime) || o.is_a?(Time)

      o.to_f
    end

    def strfz(code)

      return @zone.name if code == '%/Z'

      per = @zone.period_for_utc(utc)

      return per.abbreviation.to_s if code == '%Z'

      off = per.utc_total_offset
        #
      sn = off < 0 ? '-' : '+'; off = off.abs
      hr = off / 3600
      mn = (off % 3600) / 60
      sc = 0

      fmt =
        if code == '%z'
          "%s%02d%02d"
        elsif code == '%:z'
          "%s%02d:%02d"
        else
          "%s%02d:%02d:%02d"
        end

      fmt % [ sn, hr, mn, sc ]
    end
  end
end

