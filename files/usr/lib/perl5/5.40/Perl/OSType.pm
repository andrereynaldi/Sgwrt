use strict;
use warnings;

package Perl::OSType;

our $VERSION = '1.010';

require Exporter;
our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( all => [qw( os_type is_os_type )] );

our @EXPORT_OK = @{ $EXPORT_TAGS{all} };

my %OSTYPES = qw(
  aix         Unix
  bsdos       Unix
  beos        Unix
  bitrig      Unix
  dgux        Unix
  dragonfly   Unix
  dynixptx    Unix
  freebsd     Unix
  linux       Unix
  haiku       Unix
  hpux        Unix
  iphoneos    Unix
  irix        Unix
  darwin      Unix
  machten     Unix
  midnightbsd Unix
  minix       Unix
  mirbsd      Unix
  next        Unix
  openbsd     Unix
  netbsd      Unix
  dec_osf     Unix
  nto         Unix
  svr4        Unix
  svr5        Unix
  sco         Unix
  sco_sv      Unix
  unicos      Unix
  unicosmk    Unix
  solaris     Unix
  sunos       Unix
  cygwin      Unix
  msys        Unix
  os2         Unix
  interix     Unix
  gnu         Unix
  gnukfreebsd Unix
  nto         Unix
  qnx         Unix
  android     Unix

  dos         Windows
  MSWin32     Windows

  os390       EBCDIC
  os400       EBCDIC
  posix-bc    EBCDIC
  vmesa       EBCDIC

  MacOS       MacOS
  VMS         VMS
  vos         VOS
  riscos      RiscOS
  amigaos     Amiga
  mpeix       MPEiX
);

sub os_type {
    my ($os) = @_;
    $os = $^O unless defined $os;
    return $OSTYPES{$os} || q{};
}

sub is_os_type {
    my ( $type, $os ) = @_;
    return unless $type;
    $os = $^O unless defined $os;
    return os_type($os) eq $type;
}

1;


__END__


