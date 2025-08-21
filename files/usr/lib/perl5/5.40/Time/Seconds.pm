package Time::Seconds;
use strict;

our $VERSION = '1.3401';

use Exporter 5.57 'import';

our @EXPORT = qw(
    ONE_MINUTE
    ONE_HOUR
    ONE_DAY
    ONE_WEEK
    ONE_MONTH
    ONE_YEAR
    ONE_FINANCIAL_MONTH
    LEAP_YEAR
    NON_LEAP_YEAR
);

our @EXPORT_OK = qw(cs_sec cs_mon);

use constant {
    ONE_MINUTE => 60,
    ONE_HOUR => 3_600,
    ONE_DAY => 86_400,
    ONE_WEEK => 604_800,
    ONE_MONTH => 2_629_744, # ONE_YEAR / 12
    ONE_YEAR => 31_556_930, # 365.24225 days
    ONE_FINANCIAL_MONTH => 2_592_000, # 30 days
    LEAP_YEAR => 31_622_400, # 366 * ONE_DAY
    NON_LEAP_YEAR => 31_536_000, # 365 * ONE_DAY
    # hacks to make Time::Piece compile once again
    cs_sec => 0,
    cs_mon => 1,
};

use overload
    'fallback' => 'undef',
    '0+' => \&seconds,
    '""' => \&seconds,
    '<=>' => \&compare,
    '+' => \&add,
    '-' => \&subtract,
    '-=' => \&subtract_from,
    '+=' => \&add_to,
    '=' => \&copy;

sub new {
    my $class = shift;
    my ($val) = @_;
    $val = 0 unless defined $val;
    bless \$val, $class;
}

sub _get_ovlvals {
    my ($lhs, $rhs, $reverse) = @_;
    $lhs = $lhs->seconds;

    if (UNIVERSAL::isa($rhs, 'Time::Seconds')) {
        $rhs = $rhs->seconds;
    }
    elsif (ref($rhs)) {
        die "Can't use non Seconds object in operator overload";
    }

    if ($reverse) {
        return $rhs, $lhs;
    }

    return $lhs, $rhs;
}

sub compare {
    my ($lhs, $rhs) = _get_ovlvals(@_);
    return $lhs <=> $rhs;
}

sub add {
    my ($lhs, $rhs) = _get_ovlvals(@_);
    return Time::Seconds->new($lhs + $rhs);
}

sub add_to {
    my $lhs = shift;
    my $rhs = shift;
    $rhs = $rhs->seconds if UNIVERSAL::isa($rhs, 'Time::Seconds');
    $$lhs += $rhs;
    return $lhs;
}

sub subtract {
    my ($lhs, $rhs) = _get_ovlvals(@_);
    return Time::Seconds->new($lhs - $rhs);
}

sub subtract_from {
    my $lhs = shift;
    my $rhs = shift;
    $rhs = $rhs->seconds if UNIVERSAL::isa($rhs, 'Time::Seconds');
    $$lhs -= $rhs;
    return $lhs;
}

sub copy {
	Time::Seconds->new(${$_[0]});
}

sub seconds {
    my $s = shift;
    return $$s;
}

sub minutes {
    my $s = shift;
    return $$s / 60;
}

sub hours {
    my $s = shift;
    $s->minutes / 60;
}

sub days {
    my $s = shift;
    $s->hours / 24;
}

sub weeks {
    my $s = shift;
    $s->days / 7;
}

sub months {
    my $s = shift;
    $s->days / 30.4368541;
}

sub financial_months {
    my $s = shift;
    $s->days / 30;
}

sub years {
    my $s = shift;
    $s->days / 365.24225;
}

sub _counted_objects {
    my ($n, $counted) = @_;
    my $number = sprintf("%d", $n); # does a "floor"
    $counted .= 's' if 1 != $number;
    return ($number, $counted);
}

sub pretty {
    my $s = shift;
    my $str = "";
    if ($s < 0) {
        $s = -$s;
        $str = "minus ";
    }
    if ($s >= ONE_MINUTE) {
        if ($s >= ONE_HOUR) {
            if ($s >= ONE_DAY) {
                my ($days, $sd) = _counted_objects($s->days, "day");
                $str .= "$days $sd, ";
                $s -= ($days * ONE_DAY);
            }
            my ($hours, $sh) = _counted_objects($s->hours, "hour");
            $str .= "$hours $sh, ";
            $s -= ($hours * ONE_HOUR);
        }
        my ($mins, $sm) = _counted_objects($s->minutes, "minute");
        $str .= "$mins $sm, ";
        $s -= ($mins * ONE_MINUTE);
    }
    $str .= join " ", _counted_objects($s->seconds, "second");
    return $str;
}

1;
__END__

