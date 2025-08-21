package ExtUtils::MM_Cygwin;

use strict;
use warnings;

use ExtUtils::MakeMaker::Config;
use File::Spec;

require ExtUtils::MM_Unix;
require ExtUtils::MM_Win32;
our @ISA = qw( ExtUtils::MM_Unix );

our $VERSION = '7.70';
$VERSION =~ tr/_//d;



sub os_flavor {
    return('Unix', 'Cygwin');
}


sub cflags {
    my($self,$libperl)=@_;
    return $self->{CFLAGS} if $self->{CFLAGS};
    return '' unless $self->needs_linking();

    my $base = $self->SUPER::cflags($libperl);
    foreach (split /\n/, $base) {
        /^(\S*)\s*=\s*(\S*)$/ and $self->{$1} = $2;
    };
    $self->{CCFLAGS} .= " -DUSEIMPORTLIB" if ($Config{useshrplib} eq 'true');

    return $self->{CFLAGS} = qq{
CCFLAGS = $self->{CCFLAGS}
OPTIMIZE = $self->{OPTIMIZE}
PERLTYPE = $self->{PERLTYPE}
};

}



sub replace_manpage_separator {
    my($self, $man) = @_;
    $man =~ s{/+}{.}g;
    return $man;
}


sub init_linker {
    my $self = shift;

    if ($Config{useshrplib} eq 'true') {
        my $libperl = '$(PERL_INC)' .'/'. "$Config{libperl}";
        if( "$]" >= 5.006002 ) {
            $libperl =~ s/(dll\.)?a$/dll.a/;
        }
        $self->{PERL_ARCHIVE} = $libperl;
    } else {
        $self->{PERL_ARCHIVE} =
          '$(PERL_INC)' .'/'. ("$Config{libperl}" or "libperl.a");
    }

    $self->{PERL_ARCHIVEDEP} ||= '';
    $self->{PERL_ARCHIVE_AFTER} ||= '';
    $self->{EXPORT_LIST}  ||= '';
}

sub init_others {
    my $self = shift;

    $self->SUPER::init_others;

    $self->{LDLOADLIBS} ||= $Config{perllibs};

    return;
}


sub maybe_command {
    my ($self, $file) = @_;

    my $cygpath = Cygwin::posix_to_win_path('/', 1);
    my $filepath = Cygwin::posix_to_win_path($file, 1);

    return (substr($filepath,0,length($cygpath)) eq $cygpath)
    ? $self->SUPER::maybe_command($file) # Unix
    : ExtUtils::MM_Win32->maybe_command($file); # Win32
}


sub dynamic_lib {
    my($self, %attribs) = @_;
    my $s = ExtUtils::MM_Unix::dynamic_lib($self, %attribs);
    return '' unless $s;
    return $s unless %{$self->{XS}};

    # do an ephemeral rebase so the new DLL fits to the current rebase map
    $s .= "\t/bin/find \$\(INST_ARCHLIB\)/auto -xdev -name \\*.$self->{DLEXT} | /bin/rebase -sOT -" if (( $Config{myarchname} eq 'i686-cygwin' ) and not ( exists $ENV{CYGPORT_PACKAGE_VERSION} ));
    $s;
}


sub install {
    my($self, %attribs) = @_;
    my $s = ExtUtils::MM_Unix::install($self, %attribs);
    return '' unless $s;
    return $s unless %{$self->{XS}};

    my $INSTALLDIRS = $self->{INSTALLDIRS};
    my $INSTALLLIB = $self->{"INSTALL". ($INSTALLDIRS eq 'perl' ? 'ARCHLIB' : uc($INSTALLDIRS)."ARCH")};
    my $dop = "\$\(DESTDIR\)$INSTALLLIB/auto/";
    my $dll = "$dop/$self->{FULLEXT}/$self->{BASEEXT}.$self->{DLEXT}";
    $s =~ s|^(pure_install :: pure_\$\(INSTALLDIRS\)_install\n\t)\$\(NOECHO\) \$\(NOOP\)\n|$1\$(CHMOD) \$(PERM_RWX) $dll\n\t/bin/find $dop -xdev -name \\*.$self->{DLEXT} \| /bin/rebase -sOT -\n|m if (( $Config{myarchname} eq 'i686-cygwin') and not ( exists $ENV{CYGPORT_PACKAGE_VERSION} ));
    $s;
}


1;
