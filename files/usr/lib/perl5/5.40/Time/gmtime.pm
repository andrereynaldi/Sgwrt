package Time::gmtime 1.05;
use v5.38;

use parent 'Time::tm';

our (   $tm_sec, $tm_min, $tm_hour, $tm_mday,
        $tm_mon, $tm_year, $tm_wday, $tm_yday, 
		$tm_isdst,
);

use Exporter 'import';
our @EXPORT      = qw(gmtime gmctime);
our @EXPORT_OK   = qw(
			$tm_sec $tm_min $tm_hour $tm_mday 
			$tm_mon $tm_year $tm_wday $tm_yday 
			$tm_isdst
		    );
our %EXPORT_TAGS = ( FIELDS => [ @EXPORT_OK, @EXPORT ] );

sub populate {
    return unless @_;
    my $tmob = Time::tm->new();
    @$tmob = (
		$tm_sec, $tm_min, $tm_hour, $tm_mday, 
		$tm_mon, $tm_year, $tm_wday, $tm_yday, 
		$tm_isdst )
	    = @_;
    return $tmob;
} 

sub gmtime  :prototype(;$) { populate CORE::gmtime(@_ ? shift : time) }
sub gmctime :prototype(;$) { scalar   CORE::gmtime(@_ ? shift : time) }

__END__

