package ExtUtils::CBuilder;

use File::Spec ();
use File::Path ();
use File::Basename ();
use Perl::OSType qw/os_type/;

use warnings;
use strict;
our $VERSION = '0.280240'; # VERSION
our @ISA;

my $load = sub {
  my $mod = shift;
  eval "use $mod";
  die $@ if $@;
  @ISA = ($mod);
};

{
  my @package = split /::/, __PACKAGE__;

  my $ostype = os_type();

  if (grep {-e File::Spec->catfile($_, @package, 'Platform', $^O) . '.pm'} @INC) {
      $load->(__PACKAGE__ . "::Platform::$^O");

  } elsif ( $ostype &&
            grep {-e File::Spec->catfile($_, @package, 'Platform', $ostype) . '.pm'} @INC) {
      $load->(__PACKAGE__ . "::Platform::$ostype");

  } else {
      $load->(__PACKAGE__ . "::Base");
  }
}

1;
__END__

