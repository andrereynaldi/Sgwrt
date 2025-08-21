package Net::servent 1.04;
use v5.38;

our ( $s_name, @s_aliases, $s_port, $s_proto );

use Exporter 'import';
our @EXPORT      = qw(getservbyname getservbyport getservent getserv);
our @EXPORT_OK   = qw( $s_name @s_aliases $s_port $s_proto );
our %EXPORT_TAGS = ( FIELDS => [ @EXPORT_OK, @EXPORT ] );

use Class::Struct qw(struct);
struct 'Net::servent' => [
   name		=> '$',
   aliases	=> '@',
   port		=> '$',
   proto	=> '$',
];

sub populate {
    return unless @_;
    my $sob = new();
    $s_name 	 =    $sob->[0]     	     = $_[0];
    @s_aliases	 = @{ $sob->[1] } = split ' ', $_[1];
    $s_port	 =    $sob->[2] 	     = $_[2];
    $s_proto	 =    $sob->[3] 	     = $_[3];
    return $sob;
}

sub getservent    :prototype(   ) { populate(CORE::getservent()) }
sub getservbyname :prototype($;$) { populate(CORE::getservbyname(shift,shift||'tcp')) }
sub getservbyport :prototype($;$) { populate(CORE::getservbyport(shift,shift||'tcp')) }

sub getserv :prototype($;$) {
    no strict 'refs';
    return &{'getservby' . ($_[0]=~/^\d+$/ ? 'port' : 'name')}(@_);
}

__END__

