package ExtUtils::MakeMaker;

use strict;
use warnings;

BEGIN {require 5.006;}

require Exporter;
use ExtUtils::MakeMaker::Config;
use ExtUtils::MakeMaker::version; # ensure we always have our fake version.pm
use Carp;
use File::Path;
my $CAN_DECODE = eval { require ExtUtils::MakeMaker::Locale; }; # 2 birds, 1 stone
eval { ExtUtils::MakeMaker::Locale::reinit('UTF-8') }
  if $CAN_DECODE and Encode::find_encoding('locale')->name eq 'ascii';

our $Verbose = 0;       # exported
our @Parent;            # needs to be localized
our @Get_from_Config;   # referenced by MM_Unix
our @MM_Sections;
our @Overridable;
my @Prepend_parent;
my %Recognized_Att_Keys;
our %macro_fsentity; # whether a macro is a filesystem name
our %macro_dep; # whether a macro is a dependency

our $VERSION = '7.70';
$VERSION =~ tr/_//d;

(our $Revision = $VERSION) =~ s{_}{};
$Revision = int $Revision * 10000;

our $Filename = __FILE__;   # referenced outside MakeMaker

our @ISA = qw(Exporter);
our @EXPORT    = qw(&WriteMakefile $Verbose &prompt &os_unsupported);
our @EXPORT_OK = qw($VERSION &neatvalue &mkbootstrap &mksymlists
                    &WriteEmptyMakefile &open_for_writing &write_file_via_tmp
                    &_sprintf562);

my $Is_VMS     = $^O eq 'VMS';
my $Is_Win32   = $^O eq 'MSWin32';
our $UNDER_CORE = $ENV{PERL_CORE}; # needs to be our

full_setup();

require ExtUtils::MM;  # Things like CPAN assume loading ExtUtils::MakeMaker
                       # will give them MM.

require ExtUtils::MY;  # XXX pre-5.8 versions of ExtUtils::Embed expect
                       # loading ExtUtils::MakeMaker will give them MY.
                       # This will go when Embed is its own CPAN module.


sub _sprintf562 {
    my ($format, @args) = @_;
    for (my $i = 1; $i <= @args; $i++) {
        $format =~ s#%$i\$s#$args[$i-1]#g;
    }
    $format;
}

sub WriteMakefile {
    croak "WriteMakefile: Need even number of args" if @_ % 2;

    require ExtUtils::MY;
    my %att = @_;

    _convert_compat_attrs(\%att);

    _verify_att(\%att);

    my $mm = MM->new(\%att);
    $mm->flush;

    return $mm;
}


my %Att_Sigs;
my %Special_Sigs = (
 AUTHOR             => 'ARRAY',
 C                  => 'ARRAY',
 CONFIG             => 'ARRAY',
 CONFIGURE          => 'CODE',
 DIR                => 'ARRAY',
 DL_FUNCS           => 'HASH',
 DL_VARS            => 'ARRAY',
 EXCLUDE_EXT        => 'ARRAY',
 EXE_FILES          => 'ARRAY',
 FUNCLIST           => 'ARRAY',
 H                  => 'ARRAY',
 IMPORTS            => 'HASH',
 INCLUDE_EXT        => 'ARRAY',
 LIBS               => ['ARRAY',''],
 MAN1PODS           => 'HASH',
 MAN3PODS           => 'HASH',
 META_ADD           => 'HASH',
 META_MERGE         => 'HASH',
 OBJECT             => ['ARRAY', ''],
 PL_FILES           => 'HASH',
 PM                 => 'HASH',
 PMLIBDIRS          => 'ARRAY',
 PMLIBPARENTDIRS    => 'ARRAY',
 PREREQ_PM          => 'HASH',
 BUILD_REQUIRES     => 'HASH',
 CONFIGURE_REQUIRES => 'HASH',
 TEST_REQUIRES      => 'HASH',
 SKIP               => 'ARRAY',
 TYPEMAPS           => 'ARRAY',
 XS                 => 'HASH',
 XSBUILD            => 'HASH',
 VERSION            => ['version',''],
 _KEEP_AFTER_FLUSH  => '',

 clean      => 'HASH',
 depend     => 'HASH',
 dist       => 'HASH',
 dynamic_lib=> 'HASH',
 linkext    => 'HASH',
 macro      => 'HASH',
 postamble  => 'HASH',
 realclean  => 'HASH',
 test       => 'HASH',
 tool_autosplit => 'HASH',
);

@Att_Sigs{keys %Recognized_Att_Keys} = ('') x keys %Recognized_Att_Keys;
@Att_Sigs{keys %Special_Sigs} = values %Special_Sigs;

sub _convert_compat_attrs { #result of running several times should be same
    my($att) = @_;
    if (exists $att->{AUTHOR}) {
        if ($att->{AUTHOR}) {
            if (!ref($att->{AUTHOR})) {
                my $t = $att->{AUTHOR};
                $att->{AUTHOR} = [$t];
            }
        } else {
                $att->{AUTHOR} = [];
        }
    }
}

sub _verify_att {
    my($att) = @_;

    foreach my $key (sort keys %$att) {
        my $val = $att->{$key};
        my $sig = $Att_Sigs{$key};
        unless( defined $sig ) {
            warn "WARNING: $key is not a known parameter.\n";
            next;
        }

        my @sigs   = ref $sig ? @$sig : $sig;
        my $given  = ref $val;
        unless( grep { _is_of_type($val, $_) } @sigs ) {
            my $takes = join " or ", map { _format_att($_) } @sigs;

            my $has = _format_att($given);
            warn "WARNING: $key takes a $takes not a $has.\n".
                 "         Please inform the author.\n";
        }
    }
}


sub _is_of_type {
    my($thing, $type) = @_;

    return 1 if ref $thing eq $type;

    local $SIG{__DIE__};
    return 1 if eval{ $thing->isa($type) };

    return 0;
}


sub _format_att {
    my $given = shift;

    return $given eq ''        ? "string/number"
         : uc $given eq $given ? "$given reference"
         :                       "$given object"
         ;
}


sub prompt ($;$) {  ## no critic
    my($mess, $def) = @_;
    confess("prompt function called without an argument")
        unless defined $mess;

    my $isa_tty = -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT)) ;

    my $dispdef = defined $def ? "[$def] " : " ";
    $def = defined $def ? $def : "";

    local $|=1;
    local $\;
    print "$mess $dispdef";

    my $ans;
    if ($ENV{PERL_MM_USE_DEFAULT} || (!$isa_tty && eof STDIN)) {
        print "$def\n";
    }
    else {
        $ans = <STDIN>;
        if( defined $ans ) {
            $ans =~ s{\015?\012$}{};
        }
        else { # user hit ctrl-D
            print "\n";
        }
    }

    return (!defined $ans || $ans eq '') ? $def : $ans;
}

sub os_unsupported {
    die "OS unsupported\n";
}

sub eval_in_subdirs {
    my($self) = @_;
    use Cwd qw(cwd abs_path);
    my $pwd = cwd() || die "Can't figure out your cwd!";

    local @INC = map eval {abs_path($_) if -e} || $_, @INC;
    push @INC, '.';     # '.' has to always be at the end of @INC

    foreach my $dir (@{$self->{DIR}}){
        my($abs) = $self->catdir($pwd,$dir);
        eval { $self->eval_in_x($abs); };
        last if $@;
    }
    chdir $pwd;
    die $@ if $@;
}

sub eval_in_x {
    my($self,$dir) = @_;
    chdir $dir or carp("Couldn't change to directory $dir: $!");

    {
        package main;
        do './Makefile.PL';
    };
    if ($@) {
        die "ERROR from evaluation of $dir/Makefile.PL: $@";
    }
}


my $PACKNAME = 'PACK000';

sub full_setup {
    $Verbose ||= 0;

    my @dep_macros = qw/
    PERL_INCDEP        PERL_ARCHLIBDEP     PERL_ARCHIVEDEP
    /;

    my @fs_macros = qw/
    FULLPERL XSUBPPDIR

    INST_ARCHLIB INST_SCRIPT INST_BIN INST_LIB INST_MAN1DIR INST_MAN3DIR
    INSTALLDIRS
    DESTDIR PREFIX INSTALL_BASE
    PERLPREFIX      SITEPREFIX      VENDORPREFIX
    INSTALLPRIVLIB  INSTALLSITELIB  INSTALLVENDORLIB
    INSTALLARCHLIB  INSTALLSITEARCH INSTALLVENDORARCH
    INSTALLBIN      INSTALLSITEBIN  INSTALLVENDORBIN
    INSTALLMAN1DIR          INSTALLMAN3DIR
    INSTALLSITEMAN1DIR      INSTALLSITEMAN3DIR
    INSTALLVENDORMAN1DIR    INSTALLVENDORMAN3DIR
    INSTALLSCRIPT   INSTALLSITESCRIPT  INSTALLVENDORSCRIPT
    PERL_LIB        PERL_ARCHLIB
    SITELIBEXP      SITEARCHEXP

    MAKE LIBPERL_A LIB PERL_SRC PERL_INC
    PPM_INSTALL_EXEC PPM_UNINSTALL_EXEC
    PPM_INSTALL_SCRIPT PPM_UNINSTALL_SCRIPT
    /;

    my @attrib_help = qw/

    AUTHOR ABSTRACT ABSTRACT_FROM BINARY_LOCATION
    C CAPI CCFLAGS CONFIG CONFIGURE DEFINE DIR DISTNAME DISTVNAME
    DL_FUNCS DL_VARS
    EXCLUDE_EXT EXE_FILES FIRST_MAKEFILE
    FULLPERLRUN FULLPERLRUNINST
    FUNCLIST H IMPORTS

    INC INCLUDE_EXT LDFROM LIBS LICENSE
    LINKTYPE MAKEAPERL MAKEFILE MAKEFILE_OLD MAN1PODS MAN3PODS MAP_TARGET
    META_ADD META_MERGE MIN_PERL_VERSION BUILD_REQUIRES CONFIGURE_REQUIRES
    MYEXTLIB NAME NEEDS_LINKING NOECHO NO_META NO_MYMETA NO_PACKLIST NO_PERLLOCAL
    NORECURS NO_VC OBJECT OPTIMIZE PERL_MALLOC_OK PERL PERLMAINCC PERLRUN
    PERLRUNINST PERL_CORE
    PERM_DIR PERM_RW PERM_RWX MAGICXS
    PL_FILES PM PM_FILTER PMLIBDIRS PMLIBPARENTDIRS POLLUTE
    PREREQ_FATAL PREREQ_PM PREREQ_PRINT PRINT_PREREQ PUREPERL_ONLY
    SIGN SKIP TEST_REQUIRES TYPEMAPS UNINST VERSION VERSION_FROM XS
    XSBUILD XSMULTI XSOPT XSPROTOARG XS_VERSION
    clean depend dist dynamic_lib linkext macro realclean tool_autosplit

    MAN1EXT MAN3EXT

    MACPERL_SRC MACPERL_LIB MACLIBS_68K MACLIBS_PPC MACLIBS_SC MACLIBS_MRC
    MACLIBS_ALL_68K MACLIBS_ALL_PPC MACLIBS_SHARED
        /;
    push @attrib_help, @fs_macros;
    @macro_fsentity{@fs_macros, @dep_macros} = (1) x (@fs_macros+@dep_macros);
    @macro_dep{@dep_macros} = (1) x @dep_macros;

    # IMPORTS is used under OS/2 and Win32

    # @Overridable is close to @MM_Sections but not identical.  The
    # order is important. Many subroutines declare macros. These
    # depend on each other. Let's try to collect the macros up front,
    # then pasthru, then the rules.

    # MM_Sections are the sections we have to call explicitly
    # in Overridable we have subroutines that are used indirectly


    @MM_Sections =
        qw(

 post_initialize const_config constants platform_constants
 tool_autosplit tool_xsubpp tools_other

 makemakerdflt

 dist macro depend cflags const_loadlibs const_cccmd
 post_constants

 pasthru

 special_targets
 c_o xs_c xs_o
 top_targets blibdirs linkext dlsyms dynamic_bs dynamic
 dynamic_lib static static_lib manifypods processPL
 installbin subdirs
 clean_subdirs clean realclean_subdirs realclean
 metafile signature
 dist_basics dist_core distdir dist_test dist_ci distmeta distsignature
 install force perldepend makefile staticmake test ppd

          ); # loses section ordering

    @Overridable = @MM_Sections;
    push @Overridable, qw[

 libscan makeaperl needs_linking
 subdir_x test_via_harness test_via_script

 init_VERSION init_dist init_INST init_INSTALL init_DEST init_dirscan
 init_PM init_MANPODS init_xs init_PERL init_DIRFILESEP init_linker
                         ];

    push @MM_Sections, qw[

 pm_to_blib selfdocument

                         ];

    # Postamble needs to be the last that was always the case
    push @MM_Sections, "postamble";
    push @Overridable, "postamble";

    # All sections are valid keys.
    @Recognized_Att_Keys{@MM_Sections} = (1) x @MM_Sections;

    # we will use all these variables in the Makefile
    @Get_from_Config =
        qw(
           ar cc cccdlflags ccdlflags cpprun dlext dlsrc exe_ext full_ar ld
           lddlflags ldflags libc lib_ext obj_ext osname osvers ranlib
           sitelibexp sitearchexp so
          );

    # 5.5.3 doesn't have any concept of vendor libs
    push @Get_from_Config, qw( vendorarchexp vendorlibexp ) if "$]" >= 5.006;

    foreach my $item (@attrib_help){
        $Recognized_Att_Keys{$item} = 1;
    }
    foreach my $item (@Get_from_Config) {
        $Recognized_Att_Keys{uc $item} = $Config{$item};
        print "Attribute '\U$item\E' => '$Config{$item}'\n"
            if ($Verbose >= 2);
    }

    #
    # When we eval a Makefile.PL in a subdirectory, that one will ask
    # us (the parent) for the values and will prepend "..", so that
    # all files to be installed end up below OUR ./blib
    #
    @Prepend_parent = qw(
           INST_BIN INST_LIB INST_ARCHLIB INST_SCRIPT
           MAP_TARGET INST_MAN1DIR INST_MAN3DIR PERL_SRC
           PERL FULLPERL
    );
}

sub _has_cpan_meta_requirements {
    return eval {
      require CPAN::Meta::Requirements;
      CPAN::Meta::Requirements->VERSION(2.130);
      # Make sure vstrings can be handled. Some versions of CMR require B to
      # do this, which won't be available in miniperl.
      CPAN::Meta::Requirements->new->add_string_requirement('Module' => v1.2);
      1;
    };
}

sub new {
    my($class,$self) = @_;
    my($key);

    _convert_compat_attrs($self) if defined $self && $self;

    # Store the original args passed to WriteMakefile()
    foreach my $k (keys %$self) {
        $self->{ARGS}{$k} = $self->{$k};
    }

    $self = {} unless defined $self;

    # Temporarily bless it into MM so it can be used as an
    # object.  It will be blessed into a temp package later.
    bless $self, "MM";

    # Cleanup all the module requirement bits
    my %key2cmr;
    for my $key (qw(PREREQ_PM BUILD_REQUIRES CONFIGURE_REQUIRES TEST_REQUIRES)) {
        $self->{$key}      ||= {};
        if (_has_cpan_meta_requirements) {
            my $cmr = CPAN::Meta::Requirements->from_string_hash(
                $self->{$key},
                {
                  bad_version_hook => sub {
                    #no warnings 'numeric'; # module doesn't use warnings
                    my $fallback;
                    if ( $_[0] =~ m!^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$! ) {
                      $fallback = sprintf "%f", $_[0];
                    } else {
                      ($fallback) = $_[0] ? ($_[0] =~ /^([0-9.]+)/) : 0;
                      $fallback += 0;
                      carp "Unparsable version '$_[0]' for prerequisite $_[1] treated as $fallback";
                    }
                    version->new($fallback);
                  },
                },
            );
            $self->{$key} = $cmr->as_string_hash;
            $key2cmr{$key} = $cmr;
        } else {
            for my $module (sort keys %{ $self->{$key} }) {
                my $version = $self->{$key}->{$module};
                my $fallback = 0;
                if (!defined($version) or !length($version)) {
                    carp "Undefined requirement for $module treated as '0' (CPAN::Meta::Requirements not available)";
                }
                elsif ($version =~ /^\d+(?:\.\d+(?:_\d+)*)?$/) {
                    next;
                }
                else {
                    if ( $version =~ m!^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$! ) {
                      $fallback = sprintf "%f", $version;
                    } else {
                      ($fallback) = $version ? ($version =~ /^([0-9.]+)/) : 0;
                      $fallback += 0;
                      carp "Unparsable version '$version' for prerequisite $module treated as $fallback (CPAN::Meta::Requirements not available)";
                    }
                }
                $self->{$key}->{$module} = $fallback;
            }
        }
    }

    if ("@ARGV" =~ /\bPREREQ_PRINT\b/) {
        $self->_PREREQ_PRINT;
    }

    # PRINT_PREREQ is RedHatism.
    if ("@ARGV" =~ /\bPRINT_PREREQ\b/) {
        $self->_PRINT_PREREQ;
   }

    print "MakeMaker (v$VERSION)\n" if $Verbose;
    if (-f "MANIFEST" && ! -f "Makefile" && ! $UNDER_CORE){
        check_manifest();
    }

    check_hints($self);

    if ( $self->{MIN_PERL_VERSION}) {
        my $perl_version = $self->{MIN_PERL_VERSION};
        if (ref $perl_version) {
            # assume a version object
        }
        else {
            $perl_version = eval {
                local $SIG{__WARN__} = sub {
                    # simulate "use warnings FATAL => 'all'" for vintage perls
                    die @_;
                };
                my $v = version->new($perl_version);
                # we care about parse issues, not numify warnings
                no warnings;
                $v->numify;
            };
            $perl_version =~ tr/_//d
                if defined $perl_version;
        }

        if (!defined $perl_version) {
            # should this be a warning?
            die sprintf <<'END', $self->{MIN_PERL_VERSION};
MakeMaker FATAL: MIN_PERL_VERSION (%s) is not in a recognized format.
Recommended is a quoted numerical value like '5.005' or '5.008001'.
END
        }
        elsif ($perl_version > "$]") {
            my $message = sprintf <<'END', $perl_version, $];
Perl version %s or higher required. We run %s.
END
            if ($self->{PREREQ_FATAL}) {
                die "MakeMaker FATAL: $message";
            }
            else {
                warn "Warning: $message";
            }
        }

        $self->{MIN_PERL_VERSION} = $perl_version;
    }

    my %configure_att;         # record &{$self->{CONFIGURE}} attributes
    my(%initial_att) = %$self; # record initial attributes

    my(%unsatisfied) = ();
    my %prereq2version;
    my $cmr;
    if (_has_cpan_meta_requirements) {
        $cmr = CPAN::Meta::Requirements->new;
        for my $key (qw(PREREQ_PM BUILD_REQUIRES CONFIGURE_REQUIRES TEST_REQUIRES)) {
            $cmr->add_requirements($key2cmr{$key}) if $key2cmr{$key};
        }
        foreach my $prereq ($cmr->required_modules) {
            $prereq2version{$prereq} = $cmr->requirements_for_module($prereq);
        }
    } else {
        for my $key (qw(PREREQ_PM BUILD_REQUIRES CONFIGURE_REQUIRES TEST_REQUIRES)) {
            next unless my $module2version = $self->{$key};
            $prereq2version{$_} = $module2version->{$_} for keys %$module2version;
        }
    }
    foreach my $prereq (sort keys %prereq2version) {
        my $required_version = $prereq2version{$prereq};

        my $pr_version = 0;
        my $installed_file;

        if ( $prereq eq 'perl' ) {
          if ( defined $required_version && $required_version =~ /^v?[\d_\.]+$/
               || $required_version !~ /^v?[\d_\.]+$/ ) {
            require version;
            my $normal = eval { version->new( $required_version ) };
            $required_version = $normal if defined $normal;
          }
          $installed_file = $prereq;
          $pr_version = $];
        }
        else {
          $installed_file = MM->_installed_file_for_module($prereq);
          $pr_version = MM->parse_version($installed_file) if $installed_file;
          $pr_version = 0 if $pr_version eq 'undef';
          if ( !eval { version->new( $pr_version ); 1 } ) {
            #no warnings 'numeric'; # module doesn't use warnings
            my $fallback;
            if ( $pr_version =~ m!^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$! ) {
              $fallback = sprintf '%f', $pr_version;
            } else {
              ($fallback) = $pr_version ? ($pr_version =~ /^([0-9.]+)/) : 0;
              $fallback += 0;
              carp "Unparsable version '$pr_version' for installed prerequisite $prereq treated as $fallback";
            }
            $pr_version = $fallback;
          }
        }

        # convert X.Y_Z alpha version #s to X.YZ for easier comparisons
        $pr_version =~ s/(\d+)\.(\d+)_(\d+)/$1.$2$3/;

        if (!$installed_file) {
            warn sprintf "Warning: prerequisite %s %s not found.\n",
              $prereq, $required_version
                   unless $self->{PREREQ_FATAL}
                       or $UNDER_CORE;

            $unsatisfied{$prereq} = 'not installed';
        }
        elsif (
            $cmr
                ? !$cmr->accepts_module($prereq, $pr_version)
                : $required_version > $pr_version
        ) {
            warn sprintf "Warning: prerequisite %s %s not found. We have %s.\n",
              $prereq, $required_version, ($pr_version || 'unknown version')
                  unless $self->{PREREQ_FATAL}
                       or $UNDER_CORE;

            $unsatisfied{$prereq} = $required_version || 'unknown version' ;
        }
    }

    if (%unsatisfied && $self->{PREREQ_FATAL}){
        my $failedprereqs = join "\n", map {"    $_ $unsatisfied{$_}"}
                            sort { lc $a cmp lc $b } keys %unsatisfied;
        die <<"END";
MakeMaker FATAL: prerequisites not found.
$failedprereqs

Please install these modules first and rerun 'perl Makefile.PL'.
END
    }

    if (defined $self->{CONFIGURE}) {
        if (ref $self->{CONFIGURE} eq 'CODE') {
            %configure_att = %{&{$self->{CONFIGURE}}};
            _convert_compat_attrs(\%configure_att);
            $self = { %$self, %configure_att };
        } else {
            croak "Attribute 'CONFIGURE' to WriteMakefile() not a code reference\n";
        }
    }

    my $newclass = ++$PACKNAME;
    local @Parent = @Parent;    # Protect against non-local exits
    {
        print "Blessing Object into class [$newclass]\n" if $Verbose>=2;
        mv_all_methods("MY",$newclass);
        bless $self, $newclass;
        push @Parent, $self;
        require ExtUtils::MY;

        no strict 'refs';   ## no critic;
        @{"$newclass\:\:ISA"} = 'MM';
    }

    if (defined $Parent[-2]){
        $self->{PARENT} = $Parent[-2];
        for my $key (@Prepend_parent) {
            next unless defined $self->{PARENT}{$key};

            # Don't stomp on WriteMakefile() args.
            next if defined $self->{ARGS}{$key} and
                    $self->{ARGS}{$key} eq $self->{$key};

            $self->{$key} = $self->{PARENT}{$key};

            if ($Is_VMS && $key =~ /PERL$/) {
                # PERL or FULLPERL will be a command verb or even a
                # command with an argument instead of a full file
                # specification under VMS.  So, don't turn the command
                # into a filespec, but do add a level to the path of
                # the argument if not already absolute.
                my @cmd = split /\s+/, $self->{$key};
                $cmd[1] = $self->catfile('[-]',$cmd[1])
                  unless (@cmd < 2) || $self->file_name_is_absolute($cmd[1]);
                $self->{$key} = join(' ', @cmd);
            } else {
                my $value = $self->{$key};
                # not going to test in FS so only stripping start
                $value =~ s/"// if $key =~ /PERL$/ and $self->is_make_type('dmake');
                $value =~ s/^"// if $key =~ /PERL$/;
                $value = $self->catdir("..", $value)
                  unless $self->file_name_is_absolute($value);
                $value = qq{"$value} if $key =~ /PERL$/;
                $self->{$key} = $value;
            }
        }
        if ($self->{PARENT}) {
            $self->{PARENT}->{CHILDREN}->{$newclass} = $self;
            foreach my $opt (qw(POLLUTE PERL_CORE LINKTYPE AR FULL_AR CC CCFLAGS
                                OPTIMIZE LD LDDLFLAGS LDFLAGS PERL_ARCHLIB DESTDIR)) {
                if (exists $self->{PARENT}->{$opt}
                    and not exists $self->{$opt})
                    {
                        # inherit, but only if already unspecified
                        $self->{$opt} = $self->{PARENT}->{$opt};
                    }
            }
        }
        my @fm = grep /^FIRST_MAKEFILE=/, @ARGV;
        parse_args($self,@fm) if @fm;
    }
    else {
        parse_args($self, _shellwords($ENV{PERL_MM_OPT} || ''),@ARGV);
    }

    # RT#91540 PREREQ_FATAL not recognized on command line
    if (%unsatisfied && $self->{PREREQ_FATAL}){
        my $failedprereqs = join "\n", map {"    $_ $unsatisfied{$_}"}
                            sort { lc $a cmp lc $b } keys %unsatisfied;
        die <<"END";
MakeMaker FATAL: prerequisites not found.
$failedprereqs

Please install these modules first and rerun 'perl Makefile.PL'.
END
    }

    $self->{NAME} ||= $self->guess_name;

    warn "Warning: NAME must be a package name\n"
      unless $self->{NAME} =~ m!^[A-Z_a-z][0-9A-Z_a-z]*(?:::[0-9A-Z_a-z]+)*$!;

    ($self->{NAME_SYM} = $self->{NAME}) =~ s/\W+/_/g;

    $self->init_MAKE;
    $self->init_main;
    $self->init_VERSION;
    $self->init_dist;
    $self->init_INST;
    $self->init_INSTALL;
    $self->init_DEST;
    $self->init_dirscan;
    $self->init_PM;
    $self->init_MANPODS;
    $self->init_xs;
    $self->init_PERL;
    $self->init_DIRFILESEP;
    $self->init_linker;
    $self->init_ABSTRACT;

    $self->arch_check(
        $INC{'Config.pm'},
        $self->catfile($Config{'archlibexp'}, "Config.pm")
    );

    $self->init_tools();
    $self->init_others();
    $self->init_platform();
    $self->init_PERM();
    my @args = @ARGV;
    @args = map { Encode::decode(locale => $_) } @args if $CAN_DECODE;
    my($argv) = neatvalue(\@args);
    $argv =~ s/^\[/(/;
    $argv =~ s/\]$/)/;

    push @{$self->{RESULT}}, <<END;
END

    push @{$self->{RESULT}}, $self->_MakeMaker_Parameters_section(\%initial_att);

    if (defined $self->{CONFIGURE}) {
       push @{$self->{RESULT}}, <<END;

END
        if (scalar(keys %configure_att) > 0) {
            foreach my $key (sort keys %configure_att){
               next if $key eq 'ARGS';
               my($v) = neatvalue($configure_att{$key});
               $v =~ s/(CODE|HASH|ARRAY|SCALAR)\([\dxa-f]+\)/$1\(...\)/;
               $v =~ tr/\n/ /s;
               push @{$self->{RESULT}}, "#     $key => $v";
            }
        }
        else
        {
           push @{$self->{RESULT}}, "# no values returned";
        }
        undef %configure_att;  # free memory
    }

    # turn the SKIP array into a SKIPHASH hash
    for my $skip (@{$self->{SKIP} || []}) {
        $self->{SKIPHASH}{$skip} = 1;
    }
    delete $self->{SKIP}; # free memory

    if ($self->{PARENT}) {
        for (qw/install dist dist_basics dist_core distdir dist_test dist_ci/) {
            $self->{SKIPHASH}{$_} = 1;
        }
    }

    # We run all the subdirectories now. They don't have much to query
    # from the parent, but the parent has to query them: if they need linking!
    unless ($self->{NORECURS}) {
        $self->eval_in_subdirs if @{$self->{DIR}};
    }

    foreach my $section ( @MM_Sections ){
        # Support for new foo_target() methods.
        my $method = $section;
        $method .= '_target' unless $self->can($method);

        print "Processing Makefile '$section' section\n" if ($Verbose >= 2);
        my($skipit) = $self->skipcheck($section);
        if ($skipit){
            push @{$self->{RESULT}}, "\n# --- MakeMaker $section section $skipit.";
        } else {
            my(%a) = %{$self->{$section} || {}};
            push @{$self->{RESULT}}, "\n# --- MakeMaker $section section:";
            push @{$self->{RESULT}}, "# " . join ", ", %a if $Verbose && %a;
            push @{$self->{RESULT}}, $self->maketext_filter(
                $self->$method( %a )
            );
        }
    }

    push @{$self->{RESULT}}, "\n# End.";

    $self;
}

sub WriteEmptyMakefile {
    croak "WriteEmptyMakefile: Need an even number of args" if @_ % 2;

    my %att = @_;
    $att{DIR} = [] unless $att{DIR}; # don't recurse by default
    my $self = MM->new(\%att);

    my $new = $self->{MAKEFILE};
    my $old = $self->{MAKEFILE_OLD};
    if (-f $old) {
        _unlink($old) or warn "unlink $old: $!";
    }
    if ( -f $new ) {
        _rename($new, $old) or warn "rename $new => $old: $!"
    }
    open my $mfh, '>', $new or die "open $new for write: $!";
    print $mfh <<'EOP';
all :

manifypods :

subdirs :

dynamic :

static :

clean :

install :

makemakerdflt :

test :

test_dynamic :

test_static :

EOP
    close $mfh or die "close $new for write: $!";
}



sub _installed_file_for_module {
    my $class  = shift;
    my $prereq = shift;

    my $file = "$prereq.pm";
    $file =~ s{::}{/}g;

    my $path;
    for my $dir (@INC) {
        my $tmp = File::Spec->catfile($dir, $file);
        if ( -r $tmp ) {
            $path = $tmp;
            last;
        }
    }

    return $path;
}


sub _MakeMaker_Parameters_section {
    my $self = shift;
    my $att  = shift;

    my @result = <<'END';
END

    foreach my $key (sort keys %$att){
        next if $key eq 'ARGS';
        my $v;
        if ($key eq 'PREREQ_PM') {
            # CPAN.pm takes prereqs from this field in 'Makefile'
            # and does not know about BUILD_REQUIRES
            $v = neatvalue({
                %{ $att->{PREREQ_PM} || {} },
                %{ $att->{BUILD_REQUIRES} || {} },
                %{ $att->{TEST_REQUIRES} || {} },
            });
        } else {
            $v = neatvalue($att->{$key});
        }

        $v =~ s/(CODE|HASH|ARRAY|SCALAR)\([\dxa-f]+\)/$1\(...\)/;
        $v =~ tr/\n/ /s;
        push @result, "#     $key => $v";
    }

    return @result;
}

sub _shellwords {
    my (@lines) = @_;
    my @allwords;

    foreach my $line (@lines) {
      $line =~ s/^\s+//;
      my @words = _parse_line('\s+', 0, $line);
      pop @words if (@words and !defined $words[-1]);
      return() unless (@words || !length($line));
      push(@allwords, @words);
    }
    return(@allwords);
}

sub _parse_line {
    my($delimiter, $keep, $line) = @_;
    my($word, @pieces);

    no warnings 'uninitialized';  # we will be testing undef strings

    while (length($line)) {
        # This pattern is optimised to be stack conservative on older perls.
        # Do not refactor without being careful and testing it on very long strings.
        # See Perl bug #42980 for an example of a stack busting input.
        $line =~ s/^
                    (?:
                        # double quoted string
                        (")                             # $quote
                        ((?>[^\\"]*(?:\\.[^\\"]*)*))"   # $quoted
        | # --OR--
                        # singe quoted string
                        (')                             # $quote
                        ((?>[^\\']*(?:\\.[^\\']*)*))'   # $quoted
                    |   # --OR--
                        # unquoted string
            (                               # $unquoted
                            (?:\\.|[^\\"'])*?
                        )
                        # followed by
            (                               # $delim
                            \Z(?!\n)                    # EOL
                        |   # --OR--
                            (?-x:$delimiter)            # delimiter
                        |   # --OR--
                            (?!^)(?=["'])               # a quote
                        )
        )//xs or return;    # extended layout
        my ($quote, $quoted, $unquoted, $delim) = (($1 ? ($1,$2) : ($3,$4)), $5, $6);


  return() unless( defined($quote) || length($unquoted) || length($delim));

        if ($keep) {
      $quoted = "$quote$quoted$quote";
  }
        else {
      $unquoted =~ s/\\(.)/$1/sg;
      if (defined $quote) {
    $quoted =~ s/\\(.)/$1/sg if ($quote eq '"');
    #$quoted =~ s/\\([\\'])/$1/g if ( $PERL_SINGLE_QUOTE && $quote eq "'");
            }
  }
        $word .= substr($line, 0, 0); # leave results tainted
        $word .= defined $quote ? $quoted : $unquoted;

        if (length($delim)) {
            push(@pieces, $word);
            push(@pieces, $delim) if ($keep eq 'delimiters');
            undef $word;
        }
        if (!length($line)) {
            push(@pieces, $word);
  }
    }
    return(@pieces);
}

sub check_manifest {
    print STDOUT "Checking if your kit is complete...\n";
    require ExtUtils::Manifest;
    # avoid warning
    $ExtUtils::Manifest::Quiet = $ExtUtils::Manifest::Quiet = 1;
    my(@missed) = ExtUtils::Manifest::manicheck();
    if (@missed) {
        print "Warning: the following files are missing in your kit:\n";
        print "\t", join "\n\t", @missed;
        print "\n";
        print "Please inform the author.\n";
    } else {
        print "Looks good\n";
    }
}

sub parse_args{
    my($self, @args) = @_;
    @args = map { Encode::decode(locale => $_) } @args if $CAN_DECODE;
    foreach (@args) {
        unless (m/(.*?)=(.*)/) {
            ++$Verbose if m/^verb/;
            next;
        }
        my($name, $value) = ($1, $2);
        if ($value =~ m/^~(\w+)?/) { # tilde with optional username
            $value =~ s [^~(\w*)]
                [$1 ?
                 ((getpwnam($1))[7] || "~$1") :
                 (getpwuid($>))[7]
                 ]ex;
        }

        # Remember the original args passed it.  It will be useful later.
        $self->{ARGS}{uc $name} = $self->{uc $name} = $value;
    }

    # catch old-style 'potential_libs' and inform user how to 'upgrade'
    if (defined $self->{potential_libs}){
        my($msg)="'potential_libs' => '$self->{potential_libs}' should be";
        if ($self->{potential_libs}){
            print "$msg changed to:\n\t'LIBS' => ['$self->{potential_libs}']\n";
        } else {
            print "$msg deleted.\n";
        }
        $self->{LIBS} = [$self->{potential_libs}];
        delete $self->{potential_libs};
    }
    # catch old-style 'ARMAYBE' and inform user how to 'upgrade'
    if (defined $self->{ARMAYBE}){
        my($armaybe) = $self->{ARMAYBE};
        print "ARMAYBE => '$armaybe' should be changed to:\n",
                        "\t'dynamic_lib' => {ARMAYBE => '$armaybe'}\n";
        my(%dl) = %{$self->{dynamic_lib} || {}};
        $self->{dynamic_lib} = { %dl, ARMAYBE => $armaybe};
        delete $self->{ARMAYBE};
    }
    if (defined $self->{LDTARGET}){
        print "LDTARGET should be changed to LDFROM\n";
        $self->{LDFROM} = $self->{LDTARGET};
        delete $self->{LDTARGET};
    }
    # Turn a DIR argument on the command line into an array
    if (defined $self->{DIR} && ref \$self->{DIR} eq 'SCALAR') {
        # So they can choose from the command line, which extensions they want
        # the grep enables them to have some colons too much in case they
        # have to build a list with the shell
        $self->{DIR} = [grep $_, split ":", $self->{DIR}];
    }
    # Turn a INCLUDE_EXT argument on the command line into an array
    if (defined $self->{INCLUDE_EXT} && ref \$self->{INCLUDE_EXT} eq 'SCALAR') {
        $self->{INCLUDE_EXT} = [grep $_, split '\s+', $self->{INCLUDE_EXT}];
    }
    # Turn a EXCLUDE_EXT argument on the command line into an array
    if (defined $self->{EXCLUDE_EXT} && ref \$self->{EXCLUDE_EXT} eq 'SCALAR') {
        $self->{EXCLUDE_EXT} = [grep $_, split '\s+', $self->{EXCLUDE_EXT}];
    }

    foreach my $mmkey (sort keys %$self){
        next if $mmkey eq 'ARGS';
        print "  $mmkey => ", neatvalue($self->{$mmkey}), "\n" if $Verbose;
        print "'$mmkey' is not a known MakeMaker parameter name.\n"
            unless exists $Recognized_Att_Keys{$mmkey};
    }
    $| = 1 if $Verbose;
}

sub check_hints {
    my($self) = @_;
    # We allow extension-specific hints files.

    require File::Spec;
    my $curdir = File::Spec->curdir;

    my $hint_dir = File::Spec->catdir($curdir, "hints");
    return unless -d $hint_dir;

    # First we look for the best hintsfile we have
    my($hint)="${^O}_$Config{osvers}";
    $hint =~ s/\./_/g;
    $hint =~ s/_$//;
    return unless $hint;

    # Also try without trailing minor version numbers.
    while (1) {
        last if -f File::Spec->catfile($hint_dir, "$hint.pl");  # found
    } continue {
        last unless $hint =~ s/_[^_]*$//; # nothing to cut off
    }
    my $hint_file = File::Spec->catfile($hint_dir, "$hint.pl");

    return unless -f $hint_file;    # really there

    _run_hintfile($self, $hint_file);
}

sub _run_hintfile {
    our $self;
    local($self) = shift;       # make $self available to the hint file.
    my($hint_file) = shift;

    local($@, $!);
    print "Processing hints file $hint_file\n" if $Verbose;

    # Just in case the ./ isn't on the hint file, which File::Spec can
    # often strip off, we bung the curdir into @INC
    local @INC = (File::Spec->curdir, @INC);
    my $ret = do $hint_file;
    if( !defined $ret ) {
        my $error = $@ || $!;
        warn $error;
    }
}

sub mv_all_methods {
    my($from,$to) = @_;
    local $SIG{__WARN__} = sub {
        # can't use 'no warnings redefined', 5.6 only
        warn @_ unless $_[0] =~ /^Subroutine .* redefined/
    };
    foreach my $method (@Overridable) {
        next unless defined &{"${from}::$method"};
        no strict 'refs';   ## no critic
        *{"${to}::$method"} = \&{"${from}::$method"};

        # If we delete a method, then it will be undefined and cannot
        # be called.  But as long as we have Makefile.PLs that rely on
        # %MY:: being intact, we have to fill the hole with an
        # inheriting method:

        {
            package MY;
            my $super = "SUPER::".$method;
            *{$method} = sub {
                shift->$super(@_);
            };
        }
    }
}

sub skipcheck {
    my($self) = shift;
    my($section) = @_;
    return 'skipped' if $section eq 'metafile' && $UNDER_CORE;
    if ($section eq 'dynamic') {
        print "Warning (non-fatal): Target 'dynamic' depends on targets ",
        "in skipped section 'dynamic_bs'\n"
            if $self->{SKIPHASH}{dynamic_bs} && $Verbose;
        print "Warning (non-fatal): Target 'dynamic' depends on targets ",
        "in skipped section 'dynamic_lib'\n"
            if $self->{SKIPHASH}{dynamic_lib} && $Verbose;
    }
    if ($section eq 'dynamic_lib') {
        print "Warning (non-fatal): Target '\$(INST_DYNAMIC)' depends on ",
        "targets in skipped section 'dynamic_bs'\n"
            if $self->{SKIPHASH}{dynamic_bs} && $Verbose;
    }
    if ($section eq 'static') {
        print "Warning (non-fatal): Target 'static' depends on targets ",
        "in skipped section 'static_lib'\n"
            if $self->{SKIPHASH}{static_lib} && $Verbose;
    }
    return 'skipped' if $self->{SKIPHASH}{$section};
    return '';
}

sub open_for_writing {
    my ($file) = @_;
    open my $fh ,">", $file or die "Unable to open $file: $!";
    my @layers = ':raw';
    push @layers, join ' ', ':encoding(locale)' if $CAN_DECODE;
    binmode $fh, join ' ', @layers;
    $fh;
}

sub flush {
    my $self = shift;

    my $finalname = $self->{MAKEFILE};
    printf STDOUT "Generating a %s %s\n", $self->make_type, $finalname if $Verbose || !$self->{PARENT};
    print STDOUT "Writing $finalname for $self->{NAME}\n" if $Verbose || !$self->{PARENT};

    unlink($finalname, "MakeMaker.tmp", $Is_VMS ? 'Descrip.MMS' : ());

    write_file_via_tmp($finalname, $self->{RESULT});

    # Write MYMETA.yml to communicate metadata up to the CPAN clients
    print STDOUT "Writing MYMETA.yml and MYMETA.json\n"
      if !$self->{NO_MYMETA} and $self->write_mymeta( $self->mymeta );

    # save memory
    if ($self->{PARENT} && !$self->{_KEEP_AFTER_FLUSH}) {
        my %keep = map { ($_ => 1) } qw(NEEDS_LINKING HAS_LINK_CODE);
        delete $self->{$_} for grep !$keep{$_}, keys %$self;
    }

    system("$Config::Config{eunicefix} $finalname")
      if $Config::Config{eunicefix} ne ":";

    return;
}

sub write_file_via_tmp {
    my ($finalname, $contents) = @_;
    my $fh = open_for_writing("MakeMaker.tmp");
    die "write_file_via_tmp: 2nd arg must be ref" unless ref $contents;
    for my $chunk (@$contents) {
        my $to_write = $chunk;
        $to_write = '' unless defined $to_write;
        utf8::encode $to_write if !$CAN_DECODE && "$]" > 5.008;
        print $fh "$to_write\n" or die "Can't write to MakeMaker.tmp: $!";
    }
    close $fh or die "Can't write to MakeMaker.tmp: $!";
    _rename("MakeMaker.tmp", $finalname) or
      warn "rename MakeMaker.tmp => $finalname: $!";
    chmod 0644, $finalname if !$Is_VMS;
    return;
}

sub _rename {
    my($src, $dest) = @_;
    _unlink($dest);
    return rename $src, $dest;
}

sub _unlink {
    my @files = @_;
    chmod 0666, @files;
    return unlink @files;
}


sub mkbootstrap {
    die <<END;
!!! Your Makefile has been built such a long time ago, !!!
!!! that is unlikely to work with current MakeMaker.   !!!
!!! Please rebuild your Makefile                       !!!
END
}

sub mksymlists {
    die <<END;
!!! Your Makefile has been built such a long time ago, !!!
!!! that is unlikely to work with current MakeMaker.   !!!
!!! Please rebuild your Makefile                       !!!
END
}

sub neatvalue {
    my($v) = @_;
    return "undef" unless defined $v;
    my($t) = ref $v;
    return "q[$v]" unless $t;
    if ($t eq 'ARRAY') {
        my(@m, @neat);
        push @m, "[";
        foreach my $elem (@$v) {
            push @neat, "q[$elem]";
        }
        push @m, join ", ", @neat;
        push @m, "]";
        return join "", @m;
    }
    return $v unless $t eq 'HASH';
    my(@m, $key, $val);
    for my $key (sort keys %$v) {
        last unless defined $key; # cautious programming in case (undef,undef) is true
        push @m,"$key=>".neatvalue($v->{$key});
    }
    return "{ ".join(', ',@m)." }";
}

sub selfdocument {
    my($self) = @_;
    my(@m);
    if ($Verbose){
        push @m, "\n# Full list of MakeMaker attribute values:";
        foreach my $key (sort keys %$self){
            next if $key eq 'RESULT' || $key =~ /^[A-Z][a-z]/;
            my($v) = neatvalue($self->{$key});
            $v =~ s/(CODE|HASH|ARRAY|SCALAR)\([\dxa-f]+\)/$1\(...\)/;
            $v =~ tr/\n/ /s;
            push @m, "# $key => $v";
        }
    }
    # added here as selfdocument is not overridable
    push @m, <<'EOF';

EOF
    push @m, join "\n", map "$_ ::\n\t\$(NOECHO) \$(NOOP)\n",
        # config is so manifypods won't puke if no subdirs
        grep !$self->{SKIPHASH}{$_},
        qw(static dynamic config);
    join "\n", @m;
}

1;

__END__

