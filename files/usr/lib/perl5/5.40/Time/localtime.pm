package Time::localtime 1.04;
use v5.38;

use parent 'Time::tm';

our (  
      $tm_sec, $tm_min, $tm_hour, $tm_mday,
      $tm_mon, $tm_year, $tm_wday, $tm_yday,
      $tm_isdst
);

use Exporter   'import';
our @EXPORT      = qw(localtime ctime);
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

sub localtime :prototype(;$) { populate CORE::localtime(@_ ? shift : time) }
sub ctime     :prototype(;$) { scalar   CORE::localtime(@_ ? shift : time) }

__END__

