use v5.10;
use strict;
use warnings;
package CPAN::Meta::Requirements::Range;

our $VERSION = '2.143';

use Carp ();


use Carp ();

package
  CPAN::Meta::Requirements::Range::_Base;


BEGIN {
  eval "use version ()"; ## no critic
  if ( my $err = $@ ) {
    eval "use ExtUtils::MakeMaker::version" or die $err; ## no critic
  }
}

sub _find_magic_vstring {
  my $value = shift;
  my $tvalue = '';
  require B;
  my $sv = B::svref_2object(\$value);
  my $magic = ref($sv) eq 'B::PVMG' ? $sv->MAGIC : undef;
  while ( $magic ) {
    if ( $magic->TYPE eq 'V' ) {
      $tvalue = $magic->PTR;
      $tvalue =~ s/^v?(.+)$/v$1/;
      last;
    }
    else {
      $magic = $magic->MOREMAGIC;
    }
  }
  return $tvalue;
}

*_is_qv = version->can('is_qv') ? sub { $_[0]->is_qv } : sub { exists $_[0]->{qv} };

my $V0 = version->new(0);

sub _isa_version {
  UNIVERSAL::isa( $_[0], 'UNIVERSAL' ) && $_[0]->isa('version')
}

sub _version_object {
  my ($self, $version, $module, $bad_version_hook) = @_;

  my ($vobj, $err);

  if (not defined $version or (!ref($version) && $version eq '0')) {
    return $V0;
  }
  elsif ( ref($version) eq 'version' || ( ref($version) && _isa_version($version) ) ) {
    $vobj = $version;
  }
  else {
    # hack around version::vpp not handling <3 character vstring literals
    if ( $INC{'version/vpp.pm'} || $INC{'ExtUtils/MakeMaker/version/vpp.pm'} ) {
      my $magic = _find_magic_vstring( $version );
      $version = $magic if length $magic;
    }
    # pad to 3 characters if before 5.8.1 and appears to be a v-string
    if ( $] < 5.008001 && $version !~ /\A[0-9]/ && substr($version,0,1) ne 'v' && length($version) < 3 ) {
      $version .= "\0" x (3 - length($version));
    }
    eval {
      local $SIG{__WARN__} = sub { die "Invalid version: $_[0]" };
      # avoid specific segfault on some older version.pm versions
      die "Invalid version: $version" if $version eq 'version';
      $vobj = version->new($version);
    };
    if ( my $err = $@ ) {
      $vobj = eval { $bad_version_hook->($version, $module) }
        if ref $bad_version_hook eq 'CODE';
      unless (eval { $vobj->isa("version") }) {
        $err =~ s{ at .* line \d+.*$}{};
        die "Can't convert '$version': $err";
      }
    }
  }

  # ensure no leading '.'
  if ( $vobj =~ m{\A\.} ) {
    $vobj = version->new("0$vobj");
  }

  # ensure normal v-string form
  if ( _is_qv($vobj) ) {
    $vobj = version->new($vobj->normal);
  }

  return $vobj;
}


my %methods_for_op = (
  '==' => [ qw(with_exact_version) ],
  '!=' => [ qw(with_exclusion) ],
  '>=' => [ qw(with_minimum)   ],
  '<=' => [ qw(with_maximum)   ],
  '>'  => [ qw(with_minimum with_exclusion) ],
  '<'  => [ qw(with_maximum with_exclusion) ],
);

sub with_string_requirement {
  my ($self, $req, $module, $bad_version_hook) = @_;
  $module //= 'module';

  unless ( defined $req && length $req ) {
    $req = 0;
    Carp::carp("Undefined requirement for $module treated as '0'");
  }

  my $magic = _find_magic_vstring( $req );
  if (length $magic) {
    return $self->with_minimum($magic, $module, $bad_version_hook);
  }

  my @parts = split qr{\s*,\s*}, $req;

  for my $part (@parts) {
    my ($op, $ver) = $part =~ m{\A\s*(==|>=|>|<=|<|!=)\s*(.*)\z};

    if (! defined $op) {
      $self = $self->with_minimum($part, $module, $bad_version_hook);
    } else {
      Carp::croak("illegal requirement string: $req")
        unless my $methods = $methods_for_op{ $op };

      $self = $self->$_($ver, $module, $bad_version_hook) for @$methods;
    }
  }

  return $self;
}


sub with_range {
  my ($self, $other, $module, $bad_version_hook) = @_;
  for my $modifier($other->_as_modifiers) {
    my ($method, $arg) = @$modifier;
    $self = $self->$method($arg, $module, $bad_version_hook);
  }
  return $self;
}

package CPAN::Meta::Requirements::Range;

our @ISA = 'CPAN::Meta::Requirements::Range::_Base';

sub _clone {
  return (bless { } => $_[0]) unless ref $_[0];

  my ($s) = @_;
  my %guts = (
    (exists $s->{minimum} ? (minimum => version->new($s->{minimum})) : ()),
    (exists $s->{maximum} ? (maximum => version->new($s->{maximum})) : ()),

    (exists $s->{exclusions}
      ? (exclusions => [ map { version->new($_) } @{ $s->{exclusions} } ])
      : ()),
  );

  bless \%guts => ref($s);
}


sub with_exact_version {
  my ($self, $version, $module, $bad_version_hook) = @_;
  $module //= 'module';
  $self = $self->_clone;
  $version = $self->_version_object($version, $module, $bad_version_hook);

  unless ($self->accepts($version)) {
    $self->_reject_requirements(
      $module,
      "exact specification $version outside of range " . $self->as_string
    );
  }

  return CPAN::Meta::Requirements::Range::_Exact->_new($version);
}

sub _simplify {
  my ($self, $module) = @_;

  if (defined $self->{minimum} and defined $self->{maximum}) {
    if ($self->{minimum} == $self->{maximum}) {
      if (grep { $_ == $self->{minimum} } @{ $self->{exclusions} || [] }) {
        $self->_reject_requirements(
          $module,
          "minimum and maximum are both $self->{minimum}, which is excluded",
        );
      }

      return CPAN::Meta::Requirements::Range::_Exact->_new($self->{minimum});
    }

    if ($self->{minimum} > $self->{maximum}) {
      $self->_reject_requirements(
        $module,
        "minimum $self->{minimum} exceeds maximum $self->{maximum}",
      );
    }
  }

  # eliminate irrelevant exclusions
  if ($self->{exclusions}) {
    my %seen;
    @{ $self->{exclusions} } = grep {
      (! defined $self->{minimum} or $_ >= $self->{minimum})
      and
      (! defined $self->{maximum} or $_ <= $self->{maximum})
      and
      ! $seen{$_}++
    } @{ $self->{exclusions} };
  }

  return $self;
}


sub with_minimum {
  my ($self, $minimum, $module, $bad_version_hook) = @_;
  $module //= 'module';
  $self = $self->_clone;
  $minimum = $self->_version_object( $minimum, $module, $bad_version_hook );

  if (defined (my $old_min = $self->{minimum})) {
    $self->{minimum} = (sort { $b cmp $a } ($minimum, $old_min))[0];
  } else {
    $self->{minimum} = $minimum;
  }

  return $self->_simplify($module);
}


sub with_maximum {
  my ($self, $maximum, $module, $bad_version_hook) = @_;
  $module //= 'module';
  $self = $self->_clone;
  $maximum = $self->_version_object( $maximum, $module, $bad_version_hook );

  if (defined (my $old_max = $self->{maximum})) {
    $self->{maximum} = (sort { $a cmp $b } ($maximum, $old_max))[0];
  } else {
    $self->{maximum} = $maximum;
  }

  return $self->_simplify($module);
}


sub with_exclusion {
  my ($self, $exclusion, $module, $bad_version_hook) = @_;
  $module //= 'module';
  $self = $self->_clone;
  $exclusion = $self->_version_object( $exclusion, $module, $bad_version_hook );

  push @{ $self->{exclusions} ||= [] }, $exclusion;

  return $self->_simplify($module);
}

sub _as_modifiers {
  my ($self) = @_;
  my @mods;
  push @mods, [ with_minimum => $self->{minimum} ] if exists $self->{minimum};
  push @mods, [ with_maximum => $self->{maximum} ] if exists $self->{maximum};
  push @mods, map {; [ with_exclusion => $_ ] } @{$self->{exclusions} || []};
  return @mods;
}


sub as_struct {
  my ($self) = @_;

  return 0 if ! keys %$self;

  my @exclusions = @{ $self->{exclusions} || [] };

  my @parts;

  for my $tuple (
    [ qw( >= > minimum ) ],
    [ qw( <= < maximum ) ],
  ) {
    my ($op, $e_op, $k) = @$tuple;
    if (exists $self->{$k}) {
      my @new_exclusions = grep { $_ != $self->{ $k } } @exclusions;
      if (@new_exclusions == @exclusions) {
        push @parts, [ $op, "$self->{ $k }" ];
      } else {
        push @parts, [ $e_op, "$self->{ $k }" ];
        @exclusions = @new_exclusions;
      }
    }
  }

  push @parts, map {; [ "!=", "$_" ] } @exclusions;

  return \@parts;
}


sub as_string {
  my ($self) = @_;

  my @parts = @{ $self->as_struct };

  return $parts[0][1] if @parts == 1 and $parts[0][0] eq '>=';

  return join q{, }, map {; join q{ }, @$_ } @parts;
}

sub _reject_requirements {
  my ($self, $module, $error) = @_;
  Carp::croak("illegal requirements for $module: $error")
}


sub accepts {
  my ($self, $version) = @_;

  return if defined $self->{minimum} and $version < $self->{minimum};
  return if defined $self->{maximum} and $version > $self->{maximum};
  return if defined $self->{exclusions}
        and grep { $version == $_ } @{ $self->{exclusions} };

  return 1;
}


sub is_simple {
  my ($self) = @_;
  # XXX: This is a complete hack, but also entirely correct.
  return if $self->as_string =~ /\s/;

  return 1;
}

package
  CPAN::Meta::Requirements::Range::_Exact;

our @ISA = 'CPAN::Meta::Requirements::Range::_Base';

our $VERSION = '2.141';

BEGIN {
  eval "use version ()"; ## no critic
  if ( my $err = $@ ) {
    eval "use ExtUtils::MakeMaker::version" or die $err; ## no critic
  }
}

sub _new      { bless { version => $_[1] } => $_[0] }

sub accepts { return $_[0]{version} == $_[1] }

sub _reject_requirements {
  my ($self, $module, $error) = @_;
  Carp::croak("illegal requirements for $module: $error")
}

sub _clone {
  (ref $_[0])->_new( version->new( $_[0]{version} ) )
}

sub with_exact_version {
  my ($self, $version, $module, $bad_version_hook) = @_;
  $module //= 'module';
  $version = $self->_version_object($version, $module, $bad_version_hook);

  return $self->_clone if $self->accepts($version);

  $self->_reject_requirements(
    $module,
    "can't be exactly $version when exact requirement is already $self->{version}",
  );
}

sub with_minimum {
  my ($self, $minimum, $module, $bad_version_hook) = @_;
  $module //= 'module';
  $minimum = $self->_version_object( $minimum, $module, $bad_version_hook );

  return $self->_clone if $self->{version} >= $minimum;
  $self->_reject_requirements(
    $module,
    "minimum $minimum exceeds exact specification $self->{version}",
  );
}

sub with_maximum {
  my ($self, $maximum, $module, $bad_version_hook) = @_;
  $module //= 'module';
  $maximum = $self->_version_object( $maximum, $module, $bad_version_hook );

  return $self->_clone if $self->{version} <= $maximum;
  $self->_reject_requirements(
    $module,
    "maximum $maximum below exact specification $self->{version}",
  );
}

sub with_exclusion {
  my ($self, $exclusion, $module, $bad_version_hook) = @_;
  $module //= 'module';
  $exclusion = $self->_version_object( $exclusion, $module, $bad_version_hook );

  return $self->_clone unless $exclusion == $self->{version};
  $self->_reject_requirements(
    $module,
    "tried to exclude $exclusion, which is already exactly specified",
  );
}

sub as_string { return "== $_[0]{version}" }

sub as_struct { return [ [ '==', "$_[0]{version}" ] ] }

sub _as_modifiers { return [ with_exact_version => $_[0]{version} ] }


1;


__END__

