use v5.10;
use strict;
use warnings;
package CPAN::Meta::Requirements;

our $VERSION = '2.143';

use CPAN::Meta::Requirements::Range;


use Carp ();


my @valid_options = qw( bad_version_hook );

sub new {
  my ($class, $options) = @_;
  $options ||= {};
  Carp::croak "Argument to $class\->new() must be a hash reference"
    unless ref $options eq 'HASH';
  my %self = map {; $_ => $options->{$_}} @valid_options;

  return bless \%self => $class;
}


BEGIN {
  for my $type (qw(maximum exclusion exact_version)) {
    my $method = "with_$type";
    my $to_add = $type eq 'exact_version' ? $type : "add_$type";

    my $code = sub {
      my ($self, $name, $version) = @_;

      $self->__modify_entry_for($name, $method, $version);

      return $self;
    };

    no strict 'refs';
    *$to_add = $code;
  }
}

sub add_minimum {
  my ($self, $name, $version) = @_;

  # stringify $version so that version->new("0.00")->stringify ne "0"
  # which preserves the user's choice of "0.00" as the requirement
  if (not defined $version or "$version" eq '0') {
    return $self if $self->__entry_for($name);
    Carp::croak("can't add new requirements to finalized requirements")
      if $self->is_finalized;

    $self->{requirements}{ $name } =
      CPAN::Meta::Requirements::Range->with_minimum('0', $name);
  }
  else {
    $self->__modify_entry_for($name, 'with_minimum', $version);
  }
  return $self;
}


sub version_range_for_module {
  my ($self, $module) = @_;
  return $self->{requirements}{$module};
}


sub add_requirements {
  my ($self, $req) = @_;

  for my $module ($req->required_modules) {
    my $new_range = $req->version_range_for_module($module);
    $self->__modify_entry_for($module, 'with_range', $new_range);
  }

  return $self;
}


sub accepts_module {
  my ($self, $module, $version) = @_;

  return 1 unless my $range = $self->__entry_for($module);
  return $range->accepts($version);
}


sub clear_requirement {
  my ($self, $module) = @_;

  return $self unless $self->__entry_for($module);

  Carp::croak("can't clear requirements on finalized requirements")
    if $self->is_finalized;

  delete $self->{requirements}{ $module };

  return $self;
}


sub requirements_for_module {
  my ($self, $module) = @_;
  my $entry = $self->__entry_for($module);
  return unless $entry;
  return $entry->as_string;
}


sub structured_requirements_for_module {
  my ($self, $module) = @_;
  my $entry = $self->__entry_for($module);
  return unless $entry;
  return $entry->as_struct;
}


sub required_modules { keys %{ $_[0]{requirements} } }


sub clone {
  my ($self) = @_;
  my $new = (ref $self)->new;

  return $new->add_requirements($self);
}

sub __entry_for     { $_[0]{requirements}{ $_[1] } }

sub __modify_entry_for {
  my ($self, $name, $method, $version) = @_;

  my $fin = $self->is_finalized;
  my $old = $self->__entry_for($name);

  Carp::croak("can't add new requirements to finalized requirements")
    if $fin and not $old;

  my $new = ($old || 'CPAN::Meta::Requirements::Range')
          ->$method($version, $name, $self->{bad_version_hook});

  Carp::croak("can't modify finalized requirements")
    if $fin and $old->as_string ne $new->as_string;

  $self->{requirements}{ $name } = $new;
}


sub is_simple {
  my ($self) = @_;
  for my $module ($self->required_modules) {
    # XXX: This is a complete hack, but also entirely correct.
    return if not $self->__entry_for($module)->is_simple;
  }

  return 1;
}


sub is_finalized { $_[0]{finalized} }


sub finalize { $_[0]{finalized} = 1 }


sub as_string_hash {
  my ($self) = @_;

  my %hash = map {; $_ => $self->{requirements}{$_}->as_string }
             $self->required_modules;

  return \%hash;
}


sub add_string_requirement {
  my ($self, $module, $req) = @_;

  $self->__modify_entry_for($module, 'with_string_requirement', $req);
}


sub from_string_hash {
  my ($class, $hash, $options) = @_;

  my $self = $class->new($options);

  for my $module (keys %$hash) {
    my $req = $hash->{$module};
    $self->add_string_requirement($module, $req);
  }

  return $self;
}

1;

__END__

