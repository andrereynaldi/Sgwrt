package Time::Piece;

use strict;

use XSLoader ();
use Time::Seconds;
use Carp;
use Time::Local;
use Scalar::Util qw/ blessed /;

use Exporter ();

our @EXPORT = qw(
    localtime
    gmtime
);

our %EXPORT_TAGS = (
    ':override' => 'internal',
    );

our $VERSION = '1.3401_01';

XSLoader::load( 'Time::Piece', $VERSION );

my $DATE_SEP = '-';
my $TIME_SEP = ':';
my @MON_LIST = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @FULLMON_LIST = qw(January February March April May June July
                      August September October November December);
my @DAY_LIST = qw(Sun Mon Tue Wed Thu Fri Sat);
my @FULLDAY_LIST = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
my $IS_WIN32 = ($^O =~ /Win32/);

my $LOCALE;

use constant {
    'c_sec' => 0,
    'c_min' => 1,
    'c_hour' => 2,
    'c_mday' => 3,
    'c_mon' => 4,
    'c_year' => 5,
    'c_wday' => 6,
    'c_yday' => 7,
    'c_isdst' => 8,
    'c_epoch' => 9,
    'c_islocal' => 10,
};

sub localtime {
    unshift @_, __PACKAGE__ unless eval { $_[0]->isa('Time::Piece') };
    my $class = shift;
    my $time  = shift;
    $time = time if (!defined $time);
    $class->_mktime($time, 1);
}

sub gmtime {
    unshift @_, __PACKAGE__ unless eval { $_[0]->isa('Time::Piece') };
    my $class = shift;
    my $time  = shift;
    $time = time if (!defined $time);
    $class->_mktime($time, 0);
}


sub _is_time_struct {
    return 1 if ref($_[1]) eq 'ARRAY';
    return 1 if blessed($_[1]) && $_[1]->isa('Time::Piece');

    return 0;
}


sub new {
    my $class = shift;
    my ($time) = @_;

    my $self;

    if ($class->_is_time_struct($time)) {
        $self = $time->[c_islocal] ? $class->localtime($time) : $class->gmtime($time);
    }
    elsif (defined($time)) {
        $self = $class->localtime($time);
    }
    elsif (ref($class) && $class->isa(__PACKAGE__)) {
        $self = $class->_mktime($class->epoch, $class->[c_islocal]);
    }
    else {
        $self = $class->localtime();
    }

    return bless $self, ref($class) || $class;
}

sub parse {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my @components;

    warnings::warnif("deprecated", 
        "parse() is deprecated, use strptime() instead.");

    if (@_ > 1) {
        @components = @_;
    }
    else {
        @components = shift =~ /(\d+)$DATE_SEP(\d+)$DATE_SEP(\d+)(?:(?:T|\s+)(\d+)$TIME_SEP(\d+)(?:$TIME_SEP(\d+)))/;
        @components = reverse(@components[0..5]);
    }
    return $class->new( timelocal(@components ));
}

sub _mktime {
    my ($class, $time, $islocal) = @_;

    $class = blessed($class) || $class;

    if ($class->_is_time_struct($time)) {
        my @new_time = @$time;
        my @tm_parts = (@new_time[c_sec .. c_mon], $new_time[c_year]+1900);

        $new_time[c_epoch] = $islocal ? timelocal(@tm_parts) : timegm(@tm_parts);

        return wantarray ? @new_time : bless [@new_time[0..9], $islocal], $class;
    }
    _tzset();
    my @time = $islocal ?
            CORE::localtime($time)
                :
            CORE::gmtime($time);
    wantarray ? @time : bless [@time, $time, $islocal], $class;
}

my %_special_exports = (
  localtime => sub { my $c = $_[0]; sub { $c->localtime(@_) } },
  gmtime    => sub { my $c = $_[0]; sub { $c->gmtime(@_)    } },
);

sub export {
  my ($class, $to, @methods) = @_;
  for my $method (@methods) {
    if (exists $_special_exports{$method}) {
      no strict 'refs';
      no warnings 'redefine';
      *{$to . "::$method"} = $_special_exports{$method}->($class);
    } else {
      $class->Exporter::export($to, $method);
    }
  }
}

sub import {
    # replace CORE::GLOBAL localtime and gmtime if passed :override
    my $class = shift;
    my %params;
    map($params{$_}++,@_,@EXPORT);
    if (delete $params{':override'}) {
        $class->export('CORE::GLOBAL', keys %params);
    }
    else {
        $class->export(scalar caller, keys %params);
    }
}


sub sec {
    my $time = shift;
    $time->[c_sec];
}

*second = \&sec;

sub min {
    my $time = shift;
    $time->[c_min];
}

*minute = \&min;

sub hour {
    my $time = shift;
    $time->[c_hour];
}

sub mday {
    my $time = shift;
    $time->[c_mday];
}

*day_of_month = \&mday;

sub mon {
    my $time = shift;
    $time->[c_mon] + 1;
}

sub _mon {
    my $time = shift;
    $time->[c_mon];
}

sub month {
    my $time = shift;
    if (@_) {
        return $_[$time->[c_mon]];
    }
    elsif (@MON_LIST) {
        return $MON_LIST[$time->[c_mon]];
    }
    else {
        return $time->strftime('%b');
    }
}

*monname = \&month;

sub fullmonth {
    my $time = shift;
    if (@_) {
        return $_[$time->[c_mon]];
    }
    elsif (@FULLMON_LIST) {
        return $FULLMON_LIST[$time->[c_mon]];
    }
    else {
        return $time->strftime('%B');
    }
}

sub year {
    my $time = shift;
    $time->[c_year] + 1900;
}

sub _year {
    my $time = shift;
    $time->[c_year];
}

sub yy {
    my $time = shift;
    my $res = $time->[c_year] % 100;
    return $res > 9 ? $res : "0$res";
}

sub wday {
    my $time = shift;
    $time->[c_wday] + 1;
}

sub _wday {
    my $time = shift;
    $time->[c_wday];
}

*day_of_week = \&_wday;

sub wdayname {
    my $time = shift;
    if (@_) {
        return $_[$time->[c_wday]];
    }
    elsif (@DAY_LIST) {
        return $DAY_LIST[$time->[c_wday]];
    }
    else {
        return $time->strftime('%a');
    }
}

*day = \&wdayname;

sub fullday {
    my $time = shift;
    if (@_) {
        return $_[$time->[c_wday]];
    }
    elsif (@FULLDAY_LIST) {
        return $FULLDAY_LIST[$time->[c_wday]];
    }
    else {
        return $time->strftime('%A');
    }
}

sub yday {
    my $time = shift;
    $time->[c_yday];
}

*day_of_year = \&yday;

sub isdst {
    my $time = shift;
    $time->[c_isdst];
}

*daylight_savings = \&isdst;

sub tzoffset {
    my $time = shift;

    return Time::Seconds->new(0) unless $time->[c_islocal];

    my $epoch = $time->epoch;

    my $j = sub {

        my ($s,$n,$h,$d,$m,$y) = @_; $m += 1; $y += 1900;

        $time->_jd($y, $m, $d, $h, $n, $s);

    };

    # Compute floating offset in hours.
    #
    # Note use of crt methods so the tz is properly set...
    # See: http://perlmonks.org/?node_id=820347
    my $delta = 24 * ($j->(_crt_localtime($epoch)) - $j->(_crt_gmtime($epoch)));

    # Return value in seconds rounded to nearest minute.
    return Time::Seconds->new( int($delta * 60 + ($delta >= 0 ? 0.5 : -0.5)) * 60 );
}

sub epoch {
    my $time = shift;
    if (defined($time->[c_epoch])) {
        return $time->[c_epoch];
    }
    else {
        my $epoch = $time->[c_islocal] ?
          timelocal(@{$time}[c_sec .. c_mon], $time->[c_year]+1900)
          :
          timegm(@{$time}[c_sec .. c_mon], $time->[c_year]+1900);
        $time->[c_epoch] = $epoch;
        return $epoch;
    }
}

sub hms {
    my $time = shift;
    my $sep = @_ ? shift(@_) : $TIME_SEP;
    sprintf("%02d$sep%02d$sep%02d", $time->[c_hour], $time->[c_min], $time->[c_sec]);
}

*time = \&hms;

sub ymd {
    my $time = shift;
    my $sep = @_ ? shift(@_) : $DATE_SEP;
    sprintf("%d$sep%02d$sep%02d", $time->year, $time->mon, $time->[c_mday]);
}

*date = \&ymd;

sub mdy {
    my $time = shift;
    my $sep = @_ ? shift(@_) : $DATE_SEP;
    sprintf("%02d$sep%02d$sep%d", $time->mon, $time->[c_mday], $time->year);
}

sub dmy {
    my $time = shift;
    my $sep = @_ ? shift(@_) : $DATE_SEP;
    sprintf("%02d$sep%02d$sep%d", $time->[c_mday], $time->mon, $time->year);
}

sub datetime {
    my $time = shift;
    my %seps = (date => $DATE_SEP, T => 'T', time => $TIME_SEP, @_);
    return join($seps{T}, $time->date($seps{date}), $time->time($seps{time}));
}



sub julian_day {
    my $time = shift;
    # Correct for localtime
    $time = $time->gmtime( $time->epoch ) if $time->[c_islocal];

    # Calculate the Julian day itself
    my $jd = $time->_jd( $time->year, $time->mon, $time->mday,
                        $time->hour, $time->min, $time->sec);

    return $jd;
}

sub mjd {
    return shift->julian_day - 2_400_000.5;
}


sub _jd {
    my $self = shift;
    my ($y, $m, $d, $h, $n, $s) = @_;

    # Adjust input parameters according to the month
    $y = ( $m > 2 ? $y : $y - 1);
    $m = ( $m > 2 ? $m - 3 : $m + 9);

    # Calculate the Julian Date (assuming Julian calendar)
    my $J = int( 365.25 *( $y + 4712) )
      + int( (30.6 * $m) + 0.5)
        + 59
          + $d
            - 0.5;

    # Calculate the Gregorian Correction (since we have Gregorian dates)
    my $G = 38 - int( 0.75 * int(49+($y/100)));

    # Calculate the actual Julian Date
    my $JD = $J + $G;

    # Modify to include hours/mins/secs in floating portion.
    return $JD + ($h + ($n + $s / 60) / 60) / 24;
}

sub week {
    my $self = shift;

    my $J  = $self->julian_day;
    # Julian day is independent of time zone so add on tzoffset
    # if we are using local time here since we want the week day
    # to reflect the local time rather than UTC
    $J += ($self->tzoffset/(24*3600)) if $self->[c_islocal];

    # Now that we have the Julian day including fractions
    # convert it to an integer Julian Day Number using nearest
    # int (since the day changes at midday we convert all Julian
    # dates to following midnight).
    $J = int($J+0.5);

    use integer;
    my $d4 = ((($J + 31741 - ($J % 7)) % 146097) % 36524) % 1461;
    my $L  = $d4 / 1460;
    my $d1 = (($d4 - $L) % 365) + $L;
    return $d1 / 7 + 1;
}

sub _is_leap_year {
    my $year = shift;
    return (($year %4 == 0) && !($year % 100 == 0)) || ($year % 400 == 0)
               ? 1 : 0;
}

sub is_leap_year {
    my $time = shift;
    my $year = $time->year;
    return _is_leap_year($year);
}

my @MON_LAST = qw(31 28 31 30 31 30 31 31 30 31 30 31);

sub month_last_day {
    my $time = shift;
    my $year = $time->year;
    my $_mon = $time->_mon;
    return $MON_LAST[$_mon] + ($_mon == 1 ? _is_leap_year($year) : 0);
}

my $trans_map_common = {

    'c' => sub {
        my ( $format ) = @_;
        if($LOCALE->{PM} && $LOCALE->{AM}){
            $format =~ s/%c/%a %d %b %Y %I:%M:%S %p/;
        }
        else{
            $format =~ s/%c/%a %d %b %Y %H:%M:%S/;
        }
        return $format;
    },
    'r' => sub {
        my ( $format ) = @_;
        if($LOCALE->{PM} && $LOCALE->{AM}){
            $format =~ s/%r/%I:%M:%S %p/;
        }
        else{
            $format =~ s/%r/%H:%M:%S/;
        }
        return $format;
    },
    'X' => sub {
        my ( $format ) = @_;
        if($LOCALE->{PM} && $LOCALE->{AM}){
            $format =~ s/%X/%I:%M:%S %p/;
        }
        else{
            $format =~ s/%X/%H:%M:%S/;
        }
        return $format;
    },
};

my $strftime_trans_map = {
    %{$trans_map_common},

    'e' => sub {
        my ( $format, $time ) = @_;
        $format =~ s/%e/%d/ if $IS_WIN32;
        return $format;
    },
    'D' => sub {
        my ( $format, $time ) = @_;
        $format =~ s/%D/%m\/%d\/%y/;
        return $format;
    },
    'F' => sub {
        my ( $format, $time ) = @_;
        $format =~ s/%F/%Y-%m-%d/;
        return $format;
    },
    'R' => sub {
        my ( $format, $time ) = @_;
        $format =~ s/%R/%H:%M/;
        return $format;
    },
    's' => sub {
        #%s not portable if time parts are from gmtime since %s will
        #cause a call to native mktime (and thus uses local TZ)
        my ( $format, $time ) = @_;
        $format =~ s/%s/$time->[c_epoch]/;
        return $format;
    },
    'T' => sub {
        my ( $format, $time ) = @_;
        $format =~ s/%T/%H:%M:%S/ if $IS_WIN32;
        return $format;
    },
    'u' => sub {
        my ( $format, $time ) = @_;
        $format =~ s/%u/%w/ if $IS_WIN32;
        return $format;
    },
    'V' => sub {
        my ( $format, $time ) = @_;
        my $week = sprintf( "%02d", $time->week() );
        $format =~ s/%V/$week/ if $IS_WIN32;
        return $format;
    },
    'x' => sub {
        my ( $format, $time ) = @_;
        $format =~ s/%x/%a %d %b %Y/;
        return $format;
    },
    'z' => sub {    #%[zZ] not portable if time parts are from gmtime
        my ( $format, $time ) = @_;
        $format =~ s/%z/+0000/ if not $time->[c_islocal];
        return $format;
    },
    'Z' => sub {
        my ( $format, $time ) = @_;
        $format =~ s/%Z/UTC/ if not $time->[c_islocal];
        return $format;
    },
};

sub strftime {
    my $time = shift;
    my $format = @_ ? shift(@_) : '%a, %d %b %Y %H:%M:%S %Z';
    $format = _translate_format($format, $strftime_trans_map, $time);

    return $format unless $format =~ /%/; #if translate removes everything

    return _strftime($format, $time->epoch, $time->[c_islocal]);
}

my $strptime_trans_map = {
    %{$trans_map_common},
};

sub strptime {
    my $time = shift;
    my $string = shift;
    my $format = @_ ? shift(@_) : "%a, %d %b %Y %H:%M:%S %Z";
    my $islocal = (ref($time) ? $time->[c_islocal] : 0);
    my $locales = $LOCALE || &Time::Piece::_default_locale();
    $format = _translate_format($format, $strptime_trans_map);
    my @vals = _strptime($string, $format, $islocal, $locales);
    return scalar $time->_mktime(\@vals, $islocal);
}

sub day_list {
    shift if ref($_[0]) && $_[0]->isa(__PACKAGE__); # strip first if called as a method
    my @old = @DAY_LIST;
    if (@_) {
        @DAY_LIST = @_;
        &Time::Piece::_default_locale();
    }
    return @old;
}

sub mon_list {
    shift if ref($_[0]) && $_[0]->isa(__PACKAGE__); # strip first if called as a method
    my @old = @MON_LIST;
    if (@_) {
        @MON_LIST = @_;
        &Time::Piece::_default_locale();
    }
    return @old;
}

sub time_separator {
    shift if ref($_[0]) && $_[0]->isa(__PACKAGE__);
    my $old = $TIME_SEP;
    if (@_) {
        $TIME_SEP = $_[0];
    }
    return $old;
}

sub date_separator {
    shift if ref($_[0]) && $_[0]->isa(__PACKAGE__);
    my $old = $DATE_SEP;
    if (@_) {
        $DATE_SEP = $_[0];
    }
    return $old;
}

use overload '""' => \&cdate,
             'cmp' => \&str_compare,
             'fallback' => undef;

sub cdate {
    my $time = shift;
    if ($time->[c_islocal]) {
        return scalar(CORE::localtime($time->epoch));
    }
    else {
        return scalar(CORE::gmtime($time->epoch));
    }
}

sub str_compare {
    my ($lhs, $rhs, $reverse) = @_;

    if (blessed($rhs) && $rhs->isa('Time::Piece')) {
        $rhs = "$rhs";
    }
    return $reverse ? $rhs cmp $lhs->cdate : $lhs->cdate cmp $rhs;
}

use overload
        '-' => \&subtract,
        '+' => \&add;

sub subtract {
    my $time = shift;
    my $rhs = shift;

    if (shift)
    {
	# SWAPED is set (so someone tried an expression like NOTDATE - DATE).
	# Imitate Perl's standard behavior and return the result as if the
	# string $time resolves to was subtracted from NOTDATE.  This way,
	# classes which override this one and which have a stringify function
	# that resolves to something that looks more like a number don't need
	# to override this function.
	return $rhs - "$time";
    }

    if (blessed($rhs) && $rhs->isa('Time::Piece')) {
        return Time::Seconds->new($time->epoch - $rhs->epoch);
    }
    else {
        # rhs is seconds.
        return $time->_mktime(($time->epoch - $rhs), $time->[c_islocal]);
    }
}

sub add {
    my $time = shift;
    my $rhs = shift;

    return $time->_mktime(($time->epoch + $rhs), $time->[c_islocal]);
}

use overload
        '<=>' => \&compare;

sub get_epochs {
    my ($lhs, $rhs, $reverse) = @_;
    unless (blessed($rhs) && $rhs->isa('Time::Piece')) {
        $rhs = $lhs->new($rhs);
    }
    if ($reverse) {
        return $rhs->epoch, $lhs->epoch;
    }
    return $lhs->epoch, $rhs->epoch;
}

sub compare {
    my ($lhs, $rhs) = get_epochs(@_);
    return $lhs <=> $rhs;
}

sub add_months {
    my ($time, $num_months) = @_;

    croak("add_months requires a number of months") unless defined($num_months);

    my $final_month = $time->_mon + $num_months;
    my $num_years = 0;
    if ($final_month > 11 || $final_month < 0) {
        # these two ops required because we have no POSIX::floor and don't
        # want to load POSIX.pm
        if ($final_month < 0 && $final_month % 12 == 0) {
            $num_years = int($final_month / 12) + 1;
        }
        else {
            $num_years = int($final_month / 12);
        }
        $num_years-- if ($final_month < 0);

        $final_month = $final_month % 12;
    }

    my @vals = _mini_mktime($time->sec, $time->min, $time->hour,
                            $time->mday, $final_month, $time->year - 1900 + $num_years);
    # warn(sprintf("got %d vals: %d-%d-%d %d:%d:%d [%d]\n", scalar(@vals), reverse(@vals), $time->[c_islocal]));
    return scalar $time->_mktime(\@vals, $time->[c_islocal]);
}

sub add_years {
    my ($time, $years) = @_;
    $time->add_months($years * 12);
}

sub truncate {
    my ($time, %params) = @_;
    return $time unless exists $params{to};
    #if ($params{to} eq 'week') { return $time->_truncate_week; }
    my %units = (
        second   => 0,
        minute   => 1,
        hour     => 2,
        day      => 3,
        month    => 4,
        quarter  => 5,
        year     => 5
    );
    my $to = $units{$params{to}};
    croak "Invalid value of 'to' parameter: $params{to}" unless defined $to;
    my $start_month = 0;
    if ($params{to} eq 'quarter') {
        $start_month = int( $time->_mon / 3 ) * 3;
    }
    my @down_to = (0, 0, 0, 1, $start_month, $time->year);
    return $time->_mktime([@down_to[0..$to-1], @$time[$to..c_isdst]],
        $time->[c_islocal]);
}

sub _translate_format {
    my ( $format, $trans_map, $time ) = @_;

    $format =~ s/%%/\e\e/g; #escape the escape
    my $lexer = _build_format_lexer($format);

	while(my $flag = $lexer->() ){
        next unless exists $trans_map->{$flag};
		$format = $trans_map->{$flag}($format, $time);
	}

    $format =~ s/\e\e/%%/g;
    return $format;
}

sub _build_format_lexer {
    my $format = shift();

    #Higher Order Perl p.359 (or thereabouts)
    return sub {
        LABEL: {
        return $1 if $format =~ m/\G%([a-zA-Z])/gc; #return single char flags

        redo LABEL if $format =~ m/\G(.)/gc;
        return; #return at empty string
        }
    };
}

sub use_locale {
    #get locale month/day names from posix strftime (from Piece.xs)
    my $locales = _get_localization();

    #If AM and PM are the same, set both to ''
    if (   !$locales->{PM}
        || !$locales->{AM}
        || ( $locales->{PM} eq $locales->{AM} ) )
    {
        $locales->{PM} = '';
        $locales->{AM} = '';
    }

    $locales->{pm} = lc $locales->{PM};
    $locales->{am} = lc $locales->{AM};
    #should probably figure out how to get a
    #region specific format for %c someday
    $locales->{c_fmt} = '';

    #Set globals. If anything is
    #weird just use original
    if( @{$locales->{weekday}} < 7 ){
        @{$locales->{weekday}} = @FULLDAY_LIST;
    }
    else {
        @FULLDAY_LIST = @{$locales->{weekday}};
    }

    if( @{$locales->{wday}} < 7 ){
        @{$locales->{wday}} = @DAY_LIST;
    }
    else {
        @DAY_LIST = @{$locales->{wday}};
    }

    if( @{$locales->{month}} < 12 ){
        @{$locales->{month}} = @FULLMON_LIST;
    }else {
        @FULLMON_LIST = @{$locales->{month}};
    }

    if( @{$locales->{mon}} < 12 ){
        @{$locales->{mon}} = @MON_LIST;
    }
    else{
        @MON_LIST= @{$locales->{mon}};
    }

    $LOCALE = $locales;
}

sub _default_locale {
    my $locales = {};

    @{ $locales->{weekday} } = @FULLDAY_LIST;
    @{ $locales->{wday} }    = @DAY_LIST;
    @{ $locales->{month} }   = @FULLMON_LIST;
    @{ $locales->{mon} }     = @MON_LIST;
    $locales->{alt_month} = $locales->{month};

    $locales->{PM}    = 'PM';
    $locales->{AM}    = 'AM';
    $locales->{pm}    = 'pm';
    $locales->{am}    = 'am';
    $locales->{c_fmt} = '';

    $LOCALE = $locales;
}

sub _locale {
    return $LOCALE;
}


1;
__END__

