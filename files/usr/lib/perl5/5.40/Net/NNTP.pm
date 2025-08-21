
package Net::NNTP;

use 5.008001;

use strict;
use warnings;

use Carp;
use IO::Socket;
use Net::Cmd;
use Net::Config;
use Time::Local;

our $VERSION = "3.15";

my $ssl_class = eval {
  require IO::Socket::SSL;
  # first version with default CA on most platforms
  no warnings 'numeric';
  IO::Socket::SSL->VERSION(2.007);
} && 'IO::Socket::SSL';

my $nossl_warn = !$ssl_class &&
  'To use SSL please install IO::Socket::SSL with version>=2.007';

my $family_key = 'Domain';
my $inet6_class = eval {
  require IO::Socket::IP;
  no warnings 'numeric';
  IO::Socket::IP->VERSION(0.25) || die;
  $family_key = 'Family';
} && 'IO::Socket::IP' || eval {
  require IO::Socket::INET6;
  no warnings 'numeric';
  IO::Socket::INET6->VERSION(2.62);
} && 'IO::Socket::INET6';


sub can_ssl   { $ssl_class };
sub can_inet6 { $inet6_class };

our @ISA = ('Net::Cmd', $inet6_class || 'IO::Socket::INET');


sub new {
  my $self = shift;
  my $type = ref($self) || $self;
  my ($host, %arg);
  if (@_ % 2) {
    $host = shift;
    %arg  = @_;
  }
  else {
    %arg  = @_;
    $host = delete $arg{Host};
  }
  my $obj;

  $host ||= $ENV{NNTPSERVER} || $ENV{NEWSHOST};

  my $hosts = defined $host ? [$host] : $NetConfig{nntp_hosts};

  @{$hosts} = qw(news)
    unless @{$hosts};

  my %connect = ( Proto => 'tcp');

  if ($arg{SSL}) {
    # SSL from start
    die $nossl_warn if ! $ssl_class;
    $arg{Port} ||= 563;
    $connect{$_} = $arg{$_} for(grep { m{^SSL_} } keys %arg);
  }

  foreach my $o (qw(LocalAddr LocalPort Timeout)) {
    $connect{$o} = $arg{$o} if exists $arg{$o};
  }
  $connect{$family_key} = $arg{Domain} || $arg{Family};
  $connect{Timeout} = 120 unless defined $connect{Timeout};
  $connect{PeerPort} = $arg{Port} || 'nntp(119)';
  foreach my $h (@{$hosts}) {
    $connect{PeerAddr} = $h;
    $obj = $type->SUPER::new(%connect) or next;
    ${*$obj}{'net_nntp_host'} = $h;
    ${*$obj}{'net_nntp_arg'} = \%arg;
    if ($arg{SSL}) {
      Net::NNTP::_SSL->start_SSL($obj,%arg) or next;
    }
  }

  return
    unless defined $obj;

  $obj->autoflush(1);
  $obj->debug(exists $arg{Debug} ? $arg{Debug} : undef);

  unless ($obj->response() == CMD_OK) {
    $obj->close;
    return;
  }

  my $c = $obj->code;
  my @m = $obj->message;

  unless (exists $arg{Reader} && $arg{Reader} == 0) {

    # if server is INN and we have transfer rights the we are currently
    # talking to innd not nnrpd
    if ($obj->reader) {

      # If reader succeeds the we need to consider this code to determine postok
      $c = $obj->code;
    }
    else {

      # I want to ignore this failure, so restore the previous status.
      $obj->set_status($c, \@m);
    }
  }

  ${*$obj}{'net_nntp_post'} = $c == 200 ? 1 : 0;

  $obj;
}


sub host {
  my $me = shift;
  ${*$me}{'net_nntp_host'};
}


sub debug_text {
  my $nntp  = shift;
  my $inout = shift;
  my $text  = shift;

  if ( (ref($nntp) and $nntp->code == 350 and $text =~ /^(\S+)/)
    || ($text =~ /^(authinfo\s+pass)/io))
  {
    $text = "$1 ....\n";
  }

  $text;
}


sub postok {
  @_ == 1 or croak 'usage: $nntp->postok()';
  my $nntp = shift;
  ${*$nntp}{'net_nntp_post'} || 0;
}


sub starttls {
  my $self = shift;
  $ssl_class or die $nossl_warn;
  $self->_STARTTLS or return;
  Net::NNTP::_SSL->start_SSL($self,
    %{ ${*$self}{'net_nntp_arg'} }, # (ssl) args given in new
    @_   # more (ssl) args
  ) or return;
  return 1;
}


sub article {
  @_ >= 1 && @_ <= 3 or croak 'usage: $nntp->article([{$msgid|$msgnum}[, $fh]])';
  my $nntp = shift;
  my @fh;

  @fh = (pop) if @_ == 2 || (@_ && (ref($_[0]) || ref(\$_[0]) eq 'GLOB'));

  $nntp->_ARTICLE(@_)
    ? $nntp->read_until_dot(@fh)
    : undef;
}


sub articlefh {
  @_ >= 1 && @_ <= 2 or croak 'usage: $nntp->articlefh([{$msgid|$msgnum}])';
  my $nntp = shift;

  return unless $nntp->_ARTICLE(@_);
  return $nntp->tied_fh;
}


sub authinfo {
  @_ == 3 or croak 'usage: $nntp->authinfo($user, $pass)';
  my ($nntp, $user, $pass) = @_;

  $nntp->_AUTHINFO("USER",      $user) == CMD_MORE
    && $nntp->_AUTHINFO("PASS", $pass) == CMD_OK;
}


sub authinfo_simple {
  @_ == 3 or croak 'usage: $nntp->authinfo_simple($user, $pass)';
  my ($nntp, $user, $pass) = @_;

  $nntp->_AUTHINFO('SIMPLE') == CMD_MORE
    && $nntp->command($user, $pass)->response == CMD_OK;
}


sub body {
  @_ >= 1 && @_ <= 3 or croak 'usage: $nntp->body([{$msgid|$msgnum}[, $fh]])';
  my $nntp = shift;
  my @fh;

  @fh = (pop) if @_ == 2 || (@_ && ref($_[0]) || ref(\$_[0]) eq 'GLOB');

  $nntp->_BODY(@_)
    ? $nntp->read_until_dot(@fh)
    : undef;
}


sub bodyfh {
  @_ >= 1 && @_ <= 2 or croak 'usage: $nntp->bodyfh([{$msgid|$msgnum}])';
  my $nntp = shift;
  return unless $nntp->_BODY(@_);
  return $nntp->tied_fh;
}


sub head {
  @_ >= 1 && @_ <= 3 or croak 'usage: $nntp->head([{$msgid|$msgnum}[, $fh]])';
  my $nntp = shift;
  my @fh;

  @fh = (pop) if @_ == 2 || (@_ && ref($_[0]) || ref(\$_[0]) eq 'GLOB');

  $nntp->_HEAD(@_)
    ? $nntp->read_until_dot(@fh)
    : undef;
}


sub headfh {
  @_ >= 1 && @_ <= 2 or croak 'usage: $nntp->headfh([{$msgid|$msgnum}])';
  my $nntp = shift;
  return unless $nntp->_HEAD(@_);
  return $nntp->tied_fh;
}


sub nntpstat {
  @_ == 1 || @_ == 2 or croak 'usage: $nntp->nntpstat([{$msgid|$msgnum}])';
  my $nntp = shift;

  $nntp->_STAT(@_) && $nntp->message =~ /(<[^>]+>)/o
    ? $1
    : undef;
}


sub group {
  @_ == 1 || @_ == 2 or croak 'usage: $nntp->group([$group])';
  my $nntp = shift;
  my $grp  = ${*$nntp}{'net_nntp_group'};

  return $grp
    unless (@_ || wantarray);

  my $newgrp = shift;

  $newgrp = (defined($grp) and length($grp)) ? $grp : ""
    unless defined($newgrp) and length($newgrp);

  return 
    unless $nntp->_GROUP($newgrp) and $nntp->message =~ /(\d+)\s+(\d+)\s+(\d+)\s+(\S+)/;

  my ($count, $first, $last, $group) = ($1, $2, $3, $4);

  # group may be replied as '(current group)'
  $group = ${*$nntp}{'net_nntp_group'}
    if $group =~ /\(/;

  ${*$nntp}{'net_nntp_group'} = $group;

  wantarray
    ? ($count, $first, $last, $group)
    : $group;
}


sub help {
  @_ == 1 or croak 'usage: $nntp->help()';
  my $nntp = shift;

  $nntp->_HELP
    ? $nntp->read_until_dot
    : undef;
}


sub ihave {
  @_ >= 2 or croak 'usage: $nntp->ihave($msgid[, $message])';
  my $nntp  = shift;
  my $msgid = shift;

  $nntp->_IHAVE($msgid) && $nntp->datasend(@_)
    ? @_ == 0 || $nntp->dataend
    : undef;
}


sub last {
  @_ == 1 or croak 'usage: $nntp->last()';
  my $nntp = shift;

  $nntp->_LAST && $nntp->message =~ /(<[^>]+>)/o
    ? $1
    : undef;
}


sub list {
  @_ == 1 or croak 'usage: $nntp->list()';
  my $nntp = shift;

  $nntp->_LIST
    ? $nntp->_grouplist
    : undef;
}


sub newgroups {
  @_ >= 2 or croak 'usage: $nntp->newgroups($since[, $distributions])';
  my $nntp = shift;
  my $since = _timestr(shift);
  my $distributions = shift || "";

  $distributions = join(",", @{$distributions})
    if ref($distributions);

  $nntp->_NEWGROUPS($since, $distributions)
    ? $nntp->_grouplist
    : undef;
}


sub newnews {
  @_ >= 2 && @_ <= 4
    or croak 'usage: $nntp->newnews($since[, $groups[, $distributions]])';
  my $nntp = shift;
  my $since = _timestr(shift);
  my $groups = @_ ? shift : $nntp->group;
  my $distributions = shift || "";

  $groups ||= "*";
  $groups = join(",", @{$groups})
    if ref($groups);

  $distributions = join(",", @{$distributions})
    if ref($distributions);

  $nntp->_NEWNEWS($groups, $since, $distributions)
    ? $nntp->_articlelist
    : undef;
}


sub next {
  @_ == 1 or croak 'usage: $nntp->next()';
  my $nntp = shift;

  $nntp->_NEXT && $nntp->message =~ /(<[^>]+>)/o
    ? $1
    : undef;
}


sub post {
  @_ >= 1 or croak 'usage: $nntp->post([$message])';
  my $nntp = shift;

  $nntp->_POST() && $nntp->datasend(@_)
    ? @_ == 0 || $nntp->dataend
    : undef;
}


sub postfh {
  my $nntp = shift;
  return unless $nntp->_POST();
  return $nntp->tied_fh;
}


sub quit {
  @_ == 1 or croak 'usage: $nntp->quit()';
  my $nntp = shift;

  $nntp->_QUIT;
  $nntp->close;
}


sub slave {
  @_ == 1 or croak 'usage: $nntp->slave()';
  my $nntp = shift;

  $nntp->_SLAVE;
}



sub active {
  @_ == 1 || @_ == 2 or croak 'usage: $nntp->active([$pattern])';
  my $nntp = shift;

  $nntp->_LIST('ACTIVE', @_)
    ? $nntp->_grouplist
    : undef;
}


sub active_times {
  @_ == 1 or croak 'usage: $nntp->active_times()';
  my $nntp = shift;

  $nntp->_LIST('ACTIVE.TIMES')
    ? $nntp->_grouplist
    : undef;
}


sub distributions {
  @_ == 1 or croak 'usage: $nntp->distributions()';
  my $nntp = shift;

  $nntp->_LIST('DISTRIBUTIONS')
    ? $nntp->_description
    : undef;
}


sub distribution_patterns {
  @_ == 1 or croak 'usage: $nntp->distribution_patterns()';
  my $nntp = shift;

  my $arr;
  local $_;

  ## no critic (ControlStructures::ProhibitMutatingListFunctions)
  $nntp->_LIST('DISTRIB.PATS')
    && ($arr = $nntp->read_until_dot)
    ? [grep { /^\d/ && (chomp, $_ = [split /:/]) } @$arr]
    : undef;
}


sub newsgroups {
  @_ == 1 || @_ == 2 or croak 'usage: $nntp->newsgroups([$pattern])';
  my $nntp = shift;

  $nntp->_LIST('NEWSGROUPS', @_)
    ? $nntp->_description
    : undef;
}


sub overview_fmt {
  @_ == 1 or croak 'usage: $nntp->overview_fmt()';
  my $nntp = shift;

  $nntp->_LIST('OVERVIEW.FMT')
    ? $nntp->_articlelist
    : undef;
}


sub subscriptions {
  @_ == 1 or croak 'usage: $nntp->subscriptions()';
  my $nntp = shift;

  $nntp->_LIST('SUBSCRIPTIONS')
    ? $nntp->_articlelist
    : undef;
}


sub listgroup {
  @_ == 1 || @_ == 2 or croak 'usage: $nntp->listgroup([$group])';
  my $nntp = shift;

  $nntp->_LISTGROUP(@_)
    ? $nntp->_articlelist
    : undef;
}


sub reader {
  @_ == 1 or croak 'usage: $nntp->reader()';
  my $nntp = shift;

  $nntp->_MODE('READER');
}


sub xgtitle {
  @_ == 1 || @_ == 2 or croak 'usage: $nntp->xgtitle([$pattern])';
  my $nntp = shift;

  $nntp->_XGTITLE(@_)
    ? $nntp->_description
    : undef;
}


sub xhdr {
  @_ >= 2 && @_ <= 4 or croak 'usage: $nntp->xhdr($header[, $message_spec])';
  my $nntp = shift;
  my $header = shift;
  my $arg = _msg_arg(@_);

  $nntp->_XHDR($header, $arg)
    ? $nntp->_description
    : undef;
}


sub xover {
  @_ == 2 || @_ == 3 or croak 'usage: $nntp->xover($message_spec)';
  my $nntp = shift;
  my $arg  = _msg_arg(@_);

  $nntp->_XOVER($arg)
    ? $nntp->_fieldlist
    : undef;
}


sub xpat {
  @_ == 4 || @_ == 5 or croak 'usage: $nntp->xpat($header, $pattern, $message_spec )';
  my $nntp = shift;
  my $header = shift;
  my $pattern = shift;
  my $arg = _msg_arg(@_);

  $pattern = join(" ", @$pattern)
    if ref($pattern);

  $nntp->_XPAT($header, $arg, $pattern)
    ? $nntp->_description
    : undef;
}


sub xpath {
  @_ == 2 or croak 'usage: $nntp->xpath($message_id)';
  my ($nntp, $message_id) = @_;

  return
    unless $nntp->_XPATH($message_id);

  my $m;
  ($m = $nntp->message) =~ s/^\d+\s+//o;
  my @p = split /\s+/, $m;

  wantarray ? @p : $p[0];
}


sub xrover {
  @_ == 2 || @_ == 3 or croak 'usage: $nntp->xrover($message_spec)';
  my $nntp = shift;
  my $arg  = _msg_arg(@_);

  $nntp->_XROVER($arg)
    ? $nntp->_description
    : undef;
}


sub date {
  @_ == 1 or croak 'usage: $nntp->date()';
  my $nntp = shift;

  $nntp->_DATE
    && $nntp->message =~ /(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/
    ? timegm($6, $5, $4, $3, $2 - 1, $1)
    : undef;
}




sub _msg_arg {
  my $spec = shift;
  my $arg  = "";

  if (@_) {
    carp "Depriciated passing of two message numbers, " . "pass a reference"
      if $^W;
    $spec = [$spec, $_[0]];
  }

  if (defined $spec) {
    if (ref($spec)) {
      $arg = $spec->[0];
      if (defined $spec->[1]) {
        $arg .= "-"
          if $spec->[1] != $spec->[0];
        $arg .= $spec->[1]
          if $spec->[1] > $spec->[0];
      }
    }
    else {
      $arg = $spec;
    }
  }

  $arg;
}


sub _timestr {
  my $time = shift;
  my @g    = reverse((gmtime($time))[0 .. 5]);
  $g[1] += 1;
  $g[0] %= 100;
  sprintf "%02d%02d%02d %02d%02d%02d GMT", @g;
}


sub _grouplist {
  my $nntp = shift;
  my $arr  = $nntp->read_until_dot
    or return;

  my $hash = {};

  foreach my $ln (@$arr) {
    my @a = split(/[\s\n]+/, $ln);
    $hash->{$a[0]} = [@a[1, 2, 3]];
  }

  $hash;
}


sub _fieldlist {
  my $nntp = shift;
  my $arr  = $nntp->read_until_dot
    or return;

  my $hash = {};

  foreach my $ln (@$arr) {
    my @a = split(/[\t\n]/, $ln);
    my $m = shift @a;
    $hash->{$m} = [@a];
  }

  $hash;
}


sub _articlelist {
  my $nntp = shift;
  my $arr  = $nntp->read_until_dot;

  chomp(@$arr)
    if $arr;

  $arr;
}


sub _description {
  my $nntp = shift;
  my $arr  = $nntp->read_until_dot
    or return;

  my $hash = {};

  foreach my $ln (@$arr) {
    chomp($ln);

    $hash->{$1} = $ln
      if $ln =~ s/^\s*(\S+)\s*//o;
  }

  $hash;

}



sub _ARTICLE  { shift->command('ARTICLE',  @_)->response == CMD_OK }
sub _AUTHINFO { shift->command('AUTHINFO', @_)->response }
sub _BODY     { shift->command('BODY',     @_)->response == CMD_OK }
sub _DATE      { shift->command('DATE')->response == CMD_INFO }
sub _GROUP     { shift->command('GROUP', @_)->response == CMD_OK }
sub _HEAD      { shift->command('HEAD', @_)->response == CMD_OK }
sub _HELP      { shift->command('HELP', @_)->response == CMD_INFO }
sub _IHAVE     { shift->command('IHAVE', @_)->response == CMD_MORE }
sub _LAST      { shift->command('LAST')->response == CMD_OK }
sub _LIST      { shift->command('LIST', @_)->response == CMD_OK }
sub _LISTGROUP { shift->command('LISTGROUP', @_)->response == CMD_OK }
sub _NEWGROUPS { shift->command('NEWGROUPS', @_)->response == CMD_OK }
sub _NEWNEWS   { shift->command('NEWNEWS', @_)->response == CMD_OK }
sub _NEXT      { shift->command('NEXT')->response == CMD_OK }
sub _POST      { shift->command('POST', @_)->response == CMD_MORE }
sub _QUIT      { shift->command('QUIT', @_)->response == CMD_OK }
sub _SLAVE     { shift->command('SLAVE', @_)->response == CMD_OK }
sub _STARTTLS  { shift->command("STARTTLS")->response() == CMD_MORE }
sub _STAT      { shift->command('STAT', @_)->response == CMD_OK }
sub _MODE      { shift->command('MODE', @_)->response == CMD_OK }
sub _XGTITLE   { shift->command('XGTITLE', @_)->response == CMD_OK }
sub _XHDR      { shift->command('XHDR', @_)->response == CMD_OK }
sub _XPAT      { shift->command('XPAT', @_)->response == CMD_OK }
sub _XPATH     { shift->command('XPATH', @_)->response == CMD_OK }
sub _XOVER     { shift->command('XOVER', @_)->response == CMD_OK }
sub _XROVER    { shift->command('XROVER', @_)->response == CMD_OK }
sub _XTHREAD   { shift->unsupported }
sub _XSEARCH   { shift->unsupported }
sub _XINDEX    { shift->unsupported }



sub DESTROY {
  my $nntp = shift;
  defined(fileno($nntp)) && $nntp->quit;
}

{
  package Net::NNTP::_SSL;
  our @ISA = ( $ssl_class ? ($ssl_class):(), 'Net::NNTP' );
  sub starttls { die "NNTP connection is already in SSL mode" }
  sub start_SSL {
    my ($class,$nntp,%arg) = @_;
    delete @arg{ grep { !m{^SSL_} } keys %arg };
    ( $arg{SSL_verifycn_name} ||= $nntp->host )
        =~s{(?<!:):[\w()]+$}{}; # strip port
    $arg{SSL_hostname} = $arg{SSL_verifycn_name}
        if ! defined $arg{SSL_hostname} && $class->can_client_sni;
    my $ok = $class->SUPER::start_SSL($nntp,
      SSL_verifycn_scheme => 'nntp',
      %arg
    );
    $@ = $ssl_class->errstr if !$ok;
    return $ok;
  }
}




1;

__END__

