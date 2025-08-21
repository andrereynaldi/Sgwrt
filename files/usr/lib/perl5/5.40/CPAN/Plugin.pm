package CPAN::Plugin;

use strict;
use warnings;

our $VERSION = '0.97';

require CPAN;


sub new {                                # ;
    my ($class, %params) = @_;

    my $self = +{
        (ref $class ? (%$class) : ()),
        %params,
    };

    $self = bless $self, ref $class ? ref $class : $class;

    unless (ref $class) {
        local $_;
        no warnings 'once';
        $CPAN::META->use_inst ($_) for $self->plugin_requires;
    }

    $self;
}

sub plugin_requires {                    # ;
}

sub distribution_object {                # ;
    my ($self) = @_;
    $self->{distribution_object};
}

sub distribution {                       # ;
    my ($self) = @_;

    my $distribution = $self->distribution_object->id;
    CPAN::Shell->expand("Distribution",$distribution)
      or $self->frontend->mydie("Unknowns distribution '$distribution'\n");
}

sub distribution_info {                  # ;
    my ($self) = @_;

    CPAN::DistnameInfo->new ($self->distribution->id);
}

sub build_dir {                          # ;
    my ($self) = @_;

    my $build_dir = $self->distribution->{build_dir}
      or $self->frontend->mydie("Distribution has not been built yet, cannot proceed");
}

sub is_xs {                              #
    my ($self) = @_;

    my @xs = glob File::Spec->catfile ($self->build_dir, '*.xs'); # quick try

    unless (@xs) {
        require ExtUtils::Manifest;
        my $manifest_file = File::Spec->catfile ($self->build_dir, "MANIFEST");
        my $manifest = ExtUtils::Manifest::maniread($manifest_file);
        @xs = grep /\.xs$/, keys %$manifest;
    }

    scalar @xs;
}


package CPAN::Plugin;

1;

__END__


