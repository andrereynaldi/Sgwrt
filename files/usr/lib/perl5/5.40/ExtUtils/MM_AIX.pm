package ExtUtils::MM_AIX;

use strict;
use warnings;
our $VERSION = '7.70';
$VERSION =~ tr/_//d;

use ExtUtils::MakeMaker::Config;
require ExtUtils::MM_Unix;
our @ISA = qw(ExtUtils::MM_Unix);


sub dlsyms {
    my($self,%attribs) = @_;
    return '' unless $self->needs_linking;
    join "\n", $self->xs_dlsyms_iterator(\%attribs);
}


sub xs_dlsyms_ext {
    '.exp';
}

sub xs_dlsyms_arg {
    my($self, $file) = @_;
    my $arg = qq{-bE:${file}};
    $arg = '-Wl,'.$arg if $Config{lddlflags} =~ /-Wl,-bE:/;
    return $arg;
}

sub init_others {
    my $self = shift;
    $self->SUPER::init_others;
    # perl "hints" add -bE:$(BASEEXT).exp to LDDLFLAGS. strip that out
    # so right value can be added by xs_make_dynamic_lib to work for XSMULTI
    $self->{LDDLFLAGS} ||= $Config{lddlflags};
    $self->{LDDLFLAGS} =~ s#(\s*)\S*\Q$(BASEEXT)\E\S*(\s*)#$1$2#;
    return;
}



1;
