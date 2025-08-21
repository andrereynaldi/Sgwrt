package Net::protoent 1.03;
use v5.38;

our ( $p_name, @p_aliases, $p_proto );

use Exporter 'import';
our @EXPORT      = qw(getprotobyname getprotobynumber getprotoent getproto);
our @EXPORT_OK   = qw( $p_name @p_aliases $p_proto );
our %EXPORT_TAGS = ( FIELDS => [ @EXPORT_OK, @EXPORT ] );

use Class::Struct qw(struct);
struct 'Net::protoent' => [
   name		=> '$',
   aliases	=> '@',
   proto	=> '$',
];

sub populate {
    return unless @_;
    my $pob = new();
    $p_name 	 =    $pob->[0]     	     = $_[0];
    @p_aliases	 = @{ $pob->[1] } = split ' ', $_[1];
    $p_proto	 =    $pob->[2] 	     = $_[2];
    return $pob;
} 

sub getprotoent      :prototype( ) { populate(CORE::getprotoent()) }
sub getprotobyname   :prototype($) { populate(CORE::getprotobyname(shift)) }
sub getprotobynumber :prototype($) { populate(CORE::getprotobynumber(shift)) }

sub getproto :prototype($;$) {
    no strict 'refs';
    return &{'getprotoby' . ($_[0]=~/^\d+$/ ? 'number' : 'name')}(@_);
}

__END__

