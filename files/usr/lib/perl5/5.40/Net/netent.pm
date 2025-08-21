package Net::netent 1.02;
use v5.38;

our (
    $n_name, @n_aliases,
    $n_addrtype, $n_net
);
 
use Exporter 'import';
our @EXPORT      = qw(getnetbyname getnetbyaddr getnet);
our @EXPORT_OK   = qw(
			$n_name	    	@n_aliases
			$n_addrtype 	$n_net
		   );
our %EXPORT_TAGS = ( FIELDS => [ @EXPORT_OK, @EXPORT ] );

use Class::Struct qw(struct);
struct 'Net::netent' => [
   name		=> '$',
   aliases	=> '@',
   addrtype	=> '$',
   net		=> '$',
];

sub populate {
    return unless @_;
    my $nob = new();
    $n_name 	 =    $nob->[0]     	     = $_[0];
    @n_aliases	 = @{ $nob->[1] } = split ' ', $_[1];
    $n_addrtype  =    $nob->[2] 	     = $_[2];
    $n_net	 =    $nob->[3] 	     = $_[3];
    return $nob;
} 

sub getnetbyname :prototype($) { populate(CORE::getnetbyname(shift)) }

sub getnetbyaddr :prototype($;$) {
    my ($net, $addrtype);
    $net = shift;
    require Socket if @_;
    $addrtype = @_ ? shift : Socket::AF_INET();
    populate(CORE::getnetbyaddr($net, $addrtype)) 
} 

sub getnet :prototype($) {
    if ($_[0] =~ /^\d+(?:\.\d+(?:\.\d+(?:\.\d+)?)?)?$/) {
	require Socket;
	&getnetbyaddr(Socket::inet_aton(shift));
    } else {
	&getnetbyname;
    } 
} 

__END__

