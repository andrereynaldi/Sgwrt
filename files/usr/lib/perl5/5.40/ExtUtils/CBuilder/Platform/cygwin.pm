package ExtUtils::CBuilder::Platform::cygwin;

use warnings;
use strict;
use File::Spec;
use ExtUtils::CBuilder::Platform::Unix;

our $VERSION = '0.280240'; # VERSION
our @ISA = qw(ExtUtils::CBuilder::Platform::Unix);

sub link_executable {
  my $self = shift;
  return $self->SUPER::link_executable(@_);
}

sub link {
  my ($self, %args) = @_;

  my $lib = $self->{config}{useshrplib} ? 'libperl.dll.a' : 'libperl.a';
  $args{extra_linker_flags} = [
    File::Spec->catfile($self->perl_inc(), $lib),
    $self->split_like_shell($args{extra_linker_flags})
  ];

  return $self->SUPER::link(%args);
}

1;
