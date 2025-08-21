
package Net::SMTP;

use 5.008001;

use strict;
use warnings;

use Carp;
use IO::Socket;
use Net::Cmd;
use Net::Config;
use Socket;

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

  if ($arg{SSL}) {
    # SSL from start
    die $nossl_warn if !$ssl_class;
    $arg{Port} ||= 465;
  }

  my $hosts = defined $host ? $host : $NetConfig{smtp_hosts};
  my $obj;

  $arg{Timeout} = 120 if ! defined $arg{Timeout};

  foreach my $h (@{ref($hosts) ? $hosts : [$hosts]}) {
    $obj = $type->SUPER::new(
      PeerAddr => ($host = $h),
      PeerPort => $arg{Port} || 'smtp(25)',
      LocalAddr => $arg{LocalAddr},
      LocalPort => $arg{LocalPort},
      $family_key => $arg{Domain} || $arg{Family},
      Proto     => 'tcp',
      Timeout   => $arg{Timeout}
      )
      and last;
  }

  return
    unless defined $obj;

  ${*$obj}{'net_smtp_arg'} = \%arg;
  ${*$obj}{'net_smtp_host'} = $host;

  if ($arg{SSL}) {
    Net::SMTP::_SSL->start_SSL($obj,%arg)
      or return;
  }

  $obj->autoflush(1);

  $obj->debug(exists $arg{Debug} ? $arg{Debug} : undef);

  unless ($obj->response() == CMD_OK) {
    my $err = ref($obj) . ": " . $obj->code . " " . $obj->message;
    $obj->close();
    $@ = $err;
    return;
  }

  ${*$obj}{'net_smtp_exact_addr'} = $arg{ExactAddresses};

  (${*$obj}{'net_smtp_banner'}) = $obj->message;
  (${*$obj}{'net_smtp_domain'}) = $obj->message =~ /\A\s*(\S+)/;

  if (!exists $arg{SendHello} || $arg{SendHello}) {
    unless ($obj->hello($arg{Hello} || "")) {
      my $err = ref($obj) . ": " . $obj->code . " " . $obj->message;
      $obj->close();
      $@ = $err;
      return;
    }
  }

  $obj;
}


sub host {
  my $me = shift;
  ${*$me}{'net_smtp_host'};
}



sub banner {
  my $me = shift;

  return ${*$me}{'net_smtp_banner'} || undef;
}


sub domain {
  my $me = shift;

  return ${*$me}{'net_smtp_domain'} || undef;
}


sub etrn {
  my $self = shift;
  defined($self->supports('ETRN', 500, ["Command unknown: 'ETRN'"]))
    && $self->_ETRN(@_);
}


sub auth {
  my ($self, $username, $password) = @_;

  eval {
    require MIME::Base64;
    require Authen::SASL;
  } or $self->set_status(500, ["Need MIME::Base64 and Authen::SASL todo auth"]), return 0;

  my $mechanisms = $self->supports('AUTH', 500, ["Command unknown: 'AUTH'"]);
  return unless defined $mechanisms;

  my $sasl;

  if (ref($username) and UNIVERSAL::isa($username, 'Authen::SASL')) {
    $sasl = $username;
    my $requested_mechanisms = $sasl->mechanism();
    if (! defined($requested_mechanisms) || $requested_mechanisms eq '') {
      $sasl->mechanism($mechanisms);
    }
  }
  else {
    die "auth(username, password)" if not length $username;
    $sasl = Authen::SASL->new(
      mechanism => $mechanisms,
      callback  => {
        user     => $username,
        pass     => $password,
        authname => $username,
      },
      debug => $self->debug
    );
  }

  my $client;
  my $str;
  do {
    if ($client) {
      # $client mechanism failed, so we need to exclude this mechanism from list
      my $failed_mechanism = $client->mechanism;
      return unless defined $failed_mechanism;
      $self->debug_text("Auth mechanism failed: $failed_mechanism")
        if $self->debug;
      $mechanisms =~ s/\b\Q$failed_mechanism\E\b//;
      return unless $mechanisms =~ /\S/;
      $sasl->mechanism($mechanisms);
    }
    
    # We should probably allow the user to pass the host, but I don't
    # currently know and SASL mechanisms that are used by smtp that need it

    $client = $sasl->client_new('smtp', ${*$self}{'net_smtp_host'}, 0);
    $str    = $client->client_start;
  } while (!defined $str);

  # We don't support sasl mechanisms that encrypt the socket traffic.
  # todo that we would really need to change the ISA hierarchy
  # so we don't inherit from IO::Socket, but instead hold it in an attribute

  my @cmd = ("AUTH", $client->mechanism);
  my $code;

  push @cmd, MIME::Base64::encode_base64($str, '')
    if defined $str and length $str;

  while (($code = $self->command(@cmd)->response()) == CMD_MORE) {
    my $str2 = MIME::Base64::decode_base64(($self->message)[0]);
    $self->debug_print(0, "(decoded) " . $str2 . "\n") if $self->debug;

    $str = $client->client_step($str2);
    @cmd = (
      MIME::Base64::encode_base64($str, '')
    );

    $self->debug_print(1, "(decoded) " . $str . "\n") if $self->debug;
  }

  $code == CMD_OK;
}


sub hello {
  my $me     = shift;
  my $domain = shift || "localhost.localdomain";
  my $ok     = $me->_EHLO($domain);
  my @msg    = $me->message;

  if ($ok) {
    my $h = ${*$me}{'net_smtp_esmtp'} = {};
    foreach my $ln (@msg) {
      $h->{uc $1} = $2
        if $ln =~ /([-\w]+)\b[= \t]*([^\n]*)/;
    }
  }
  elsif ($me->status == CMD_ERROR) {
    @msg = $me->message
      if $ok = $me->_HELO($domain);
  }

  return unless $ok;
  ${*$me}{net_smtp_hello_domain} = $domain;

  $msg[0] =~ /\A\s*(\S+)/;
  return ($1 || " ");
}

sub starttls {
  my $self = shift;
  $ssl_class or die $nossl_warn;
  $self->_STARTTLS or return;
  Net::SMTP::_SSL->start_SSL($self,
    %{ ${*$self}{'net_smtp_arg'} }, # (ssl) args given in new
    @_   # more (ssl) args
  ) or return;

  # another hello after starttls to read new ESMTP capabilities
  return $self->hello(${*$self}{net_smtp_hello_domain});
}


sub supports {
  my $self = shift;
  my $cmd  = uc shift;
  return ${*$self}{'net_smtp_esmtp'}->{$cmd}
    if exists ${*$self}{'net_smtp_esmtp'}->{$cmd};
  $self->set_status(@_)
    if @_;
  return;
}


sub _addr {
  my $self = shift;
  my $addr = shift;
  $addr = "" unless defined $addr;

  if (${*$self}{'net_smtp_exact_addr'}) {
    return $1 if $addr =~ /^\s*(<.*>)\s*$/s;
  }
  else {
    return $1 if $addr =~ /(<[^>]*>)/;
    $addr =~ s/^\s+|\s+$//sg;
  }

  "<$addr>";
}


sub mail {
  my $me   = shift;
  my $addr = _addr($me, shift);
  my $opts = "";

  if (@_) {
    my %opt = @_;
    my ($k, $v);

    if (exists ${*$me}{'net_smtp_esmtp'}) {
      my $esmtp = ${*$me}{'net_smtp_esmtp'};

      if (defined($v = delete $opt{Size})) {
        if (exists $esmtp->{SIZE}) {
          $opts .= sprintf " SIZE=%d", $v + 0;
        }
        else {
          carp 'Net::SMTP::mail: SIZE option not supported by host';
        }
      }

      if (defined($v = delete $opt{Return})) {
        if (exists $esmtp->{DSN}) {
          $opts .= " RET=" . ((uc($v) eq "FULL") ? "FULL" : "HDRS");
        }
        else {
          carp 'Net::SMTP::mail: DSN option not supported by host';
        }
      }

      if (defined($v = delete $opt{Bits})) {
        if ($v eq "8") {
          if (exists $esmtp->{'8BITMIME'}) {
            $opts .= " BODY=8BITMIME";
          }
          else {
            carp 'Net::SMTP::mail: 8BITMIME option not supported by host';
          }
        }
        elsif ($v eq "binary") {
          if (exists $esmtp->{'BINARYMIME'} && exists $esmtp->{'CHUNKING'}) {
            $opts .= " BODY=BINARYMIME";
            ${*$me}{'net_smtp_chunking'} = 1;
          }
          else {
            carp 'Net::SMTP::mail: BINARYMIME option not supported by host';
          }
        }
        elsif (exists $esmtp->{'8BITMIME'} or exists $esmtp->{'BINARYMIME'}) {
          $opts .= " BODY=7BIT";
        }
        else {
          carp 'Net::SMTP::mail: 8BITMIME and BINARYMIME options not supported by host';
        }
      }

      if (defined($v = delete $opt{Transaction})) {
        if (exists $esmtp->{CHECKPOINT}) {
          $opts .= " TRANSID=" . _addr($me, $v);
        }
        else {
          carp 'Net::SMTP::mail: CHECKPOINT option not supported by host';
        }
      }

      if (defined($v = delete $opt{Envelope})) {
        if (exists $esmtp->{DSN}) {
          $v =~ s/([^\041-\176]|=|\+)/sprintf "+%02X", ord($1)/sge;
          $opts .= " ENVID=$v";
        }
        else {
          carp 'Net::SMTP::mail: DSN option not supported by host';
        }
      }

      if (defined($v = delete $opt{ENVID})) {

        # expected to be in a format as required by RFC 3461, xtext-encoded
        if (exists $esmtp->{DSN}) {
          $opts .= " ENVID=$v";
        }
        else {
          carp 'Net::SMTP::mail: DSN option not supported by host';
        }
      }

      if (defined($v = delete $opt{AUTH})) {

        # expected to be in a format as required by RFC 2554,
        # rfc2821-quoted and xtext-encoded, or <>
        if (exists $esmtp->{AUTH}) {
          $v = '<>' if !defined($v) || $v eq '';
          $opts .= " AUTH=$v";
        }
        else {
          carp 'Net::SMTP::mail: AUTH option not supported by host';
        }
      }

      if (defined($v = delete $opt{XVERP})) {
        if (exists $esmtp->{'XVERP'}) {
          $opts .= " XVERP";
        }
        else {
          carp 'Net::SMTP::mail: XVERP option not supported by host';
        }
      }

      carp 'Net::SMTP::recipient: unknown option(s) ' . join(" ", keys %opt) . ' - ignored'
        if scalar keys %opt;
    }
    else {
      carp 'Net::SMTP::mail: ESMTP not supported by host - options discarded :-(';
    }
  }

  $me->_MAIL("FROM:" . $addr . $opts);
}


sub send          { my $me = shift; $me->_SEND("FROM:" . _addr($me, $_[0])) }
sub send_or_mail  { my $me = shift; $me->_SOML("FROM:" . _addr($me, $_[0])) }
sub send_and_mail { my $me = shift; $me->_SAML("FROM:" . _addr($me, $_[0])) }


sub reset {
  my $me = shift;

  $me->dataend()
    if (exists ${*$me}{'net_smtp_lastch'});

  $me->_RSET();
}


sub recipient {
  my $smtp     = shift;
  my $opts     = "";
  my $skip_bad = 0;

  if (@_ && ref($_[-1])) {
    my %opt = %{pop(@_)};
    my $v;

    $skip_bad = delete $opt{'SkipBad'};

    if (exists ${*$smtp}{'net_smtp_esmtp'}) {
      my $esmtp = ${*$smtp}{'net_smtp_esmtp'};

      if (defined($v = delete $opt{Notify})) {
        if (exists $esmtp->{DSN}) {
          $opts .= " NOTIFY=" . join(",", map { uc $_ } @$v);
        }
        else {
          carp 'Net::SMTP::recipient: DSN option not supported by host';
        }
      }

      if (defined($v = delete $opt{ORcpt})) {
        if (exists $esmtp->{DSN}) {
          $opts .= " ORCPT=" . $v;
        }
        else {
          carp 'Net::SMTP::recipient: DSN option not supported by host';
        }
      }

      carp 'Net::SMTP::recipient: unknown option(s) ' . join(" ", keys %opt) . ' - ignored'
        if scalar keys %opt;
    }
    elsif (%opt) {
      carp 'Net::SMTP::recipient: ESMTP not supported by host - options discarded :-(';
    }
  }

  my @ok;
  foreach my $addr (@_) {
    if ($smtp->_RCPT("TO:" . _addr($smtp, $addr) . $opts)) {
      push(@ok, $addr) if $skip_bad;
    }
    elsif (!$skip_bad) {
      return 0;
    }
  }

  return $skip_bad ? @ok : 1;
}

BEGIN {
  *to  = \&recipient;
  *cc  = \&recipient;
  *bcc = \&recipient;
}


sub data {
  my $me = shift;

  if (exists ${*$me}{'net_smtp_chunking'}) {
    carp 'Net::SMTP::data: CHUNKING extension in use, must call bdat instead';
  }
  else {
    my $ok = $me->_DATA() && $me->datasend(@_);

    $ok && @_
      ? $me->dataend
      : $ok;
  }
}


sub bdat {
  my $me = shift;

  if (exists ${*$me}{'net_smtp_chunking'}) {
    my $data = shift;

    $me->_BDAT(length $data)
      && $me->rawdatasend($data)
      && $me->response() == CMD_OK;
  }
  else {
    carp 'Net::SMTP::bdat: CHUNKING extension is not in use, call data instead';
  }
}


sub bdatlast {
  my $me = shift;

  if (exists ${*$me}{'net_smtp_chunking'}) {
    my $data = shift;

    $me->_BDAT(length $data, "LAST")
      && $me->rawdatasend($data)
      && $me->response() == CMD_OK;
  }
  else {
    carp 'Net::SMTP::bdat: CHUNKING extension is not in use, call data instead';
  }
}


sub datafh {
  my $me = shift;
  return unless $me->_DATA();
  return $me->tied_fh;
}


sub expand {
  my $me = shift;

  $me->_EXPN(@_)
    ? ($me->message)
    : ();
}


sub verify { shift->_VRFY(@_) }


sub help {
  my $me = shift;

  $me->_HELP(@_)
    ? scalar $me->message
    : undef;
}


sub quit {
  my $me = shift;

  $me->_QUIT;
  $me->close;
}


sub DESTROY {

  # ignore
}



sub _EHLO { shift->command("EHLO", @_)->response() == CMD_OK }
sub _HELO { shift->command("HELO", @_)->response() == CMD_OK }
sub _MAIL { shift->command("MAIL", @_)->response() == CMD_OK }
sub _RCPT { shift->command("RCPT", @_)->response() == CMD_OK }
sub _SEND { shift->command("SEND", @_)->response() == CMD_OK }
sub _SAML { shift->command("SAML", @_)->response() == CMD_OK }
sub _SOML { shift->command("SOML", @_)->response() == CMD_OK }
sub _VRFY { shift->command("VRFY", @_)->response() == CMD_OK }
sub _EXPN { shift->command("EXPN", @_)->response() == CMD_OK }
sub _HELP { shift->command("HELP", @_)->response() == CMD_OK }
sub _RSET { shift->command("RSET")->response() == CMD_OK }
sub _NOOP { shift->command("NOOP")->response() == CMD_OK }
sub _QUIT { shift->command("QUIT")->response() == CMD_OK }
sub _DATA { shift->command("DATA")->response() == CMD_MORE }
sub _BDAT { shift->command("BDAT", @_) }
sub _TURN { shift->unsupported(@_); }
sub _ETRN { shift->command("ETRN", @_)->response() == CMD_OK }
sub _AUTH { shift->command("AUTH", @_)->response() == CMD_OK }
sub _STARTTLS { shift->command("STARTTLS")->response() == CMD_OK }


{
  package Net::SMTP::_SSL;
  our @ISA = ( $ssl_class ? ($ssl_class):(), 'Net::SMTP' );
  sub starttls { die "SMTP connection is already in SSL mode" }
  sub start_SSL {
    my ($class,$smtp,%arg) = @_;
    delete @arg{ grep { !m{^SSL_} } keys %arg };
    ( $arg{SSL_verifycn_name} ||= $smtp->host )
        =~s{(?<!:):[\w()]+$}{}; # strip port
    $arg{SSL_hostname} = $arg{SSL_verifycn_name}
        if ! defined $arg{SSL_hostname} && $class->can_client_sni;
    $arg{SSL_verifycn_scheme} ||= 'smtp';
    my $ok = $class->SUPER::start_SSL($smtp,%arg);
    $@ = $ssl_class->errstr if !$ok;
    return $ok;
  }
}



1;

__END__

