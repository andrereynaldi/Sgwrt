package Net::Ping;

require 5.002;
require Exporter;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION
            $def_timeout $def_proto $def_factor $def_family
            $max_datasize $pingstring $hires $source_verify $syn_forking);
use Fcntl qw( F_GETFL F_SETFL O_NONBLOCK );
use Socket 2.007;
use Socket qw( SOCK_DGRAM SOCK_STREAM SOCK_RAW AF_INET PF_INET IPPROTO_TCP
	       SOL_SOCKET SO_ERROR SO_BROADCAST
               IPPROTO_IP IP_TOS IP_TTL
               inet_ntoa inet_aton getnameinfo sockaddr_in );
use POSIX qw( ENOTCONN ECONNREFUSED ECONNRESET EINPROGRESS EWOULDBLOCK EAGAIN
	      WNOHANG );
use FileHandle;
use Carp;
use Time::HiRes;

@ISA = qw(Exporter);
@EXPORT = qw(pingecho);
@EXPORT_OK = qw(wakeonlan);
$VERSION = "2.76";


$def_timeout = 5;           # Default timeout to wait for a reply
$def_proto = "tcp";         # Default protocol to use for pinging
$def_factor = 1.2;          # Default exponential backoff rate.
$def_family = AF_INET;      # Default family.
$max_datasize = 65535;      # Maximum data bytes. recommended: 1472 (Ethernet MTU: 1500)
$pingstring = "pingschwingping!\n";
$source_verify = 1;         # Default is to verify source endpoint
$syn_forking = 0;


my $AF_INET6  = eval { Socket::AF_INET6() } || 30;
my $AF_UNSPEC = eval { Socket::AF_UNSPEC() };
my $AI_NUMERICHOST = eval { Socket::AI_NUMERICHOST() } || 4;
my $NI_NUMERICHOST = eval { Socket::NI_NUMERICHOST() } || 2;
my $IPPROTO_IPV6   = eval { Socket::IPPROTO_IPV6() }   || 41;
my $NIx_NOSERV = eval { Socket::NIx_NOSERV() } || 2;
my $qr_family = qr/^(?:(?:(:?ip)?v?(?:4|6))|${\AF_INET}|$AF_INET6)$/;
my $qr_family4 = qr/^(?:(?:(:?ip)?v?4)|${\AF_INET})$/;
my $Socket_VERSION = eval $Socket::VERSION;

if ($^O =~ /Win32/i) {
  # Hack to avoid this Win32 spewage:
  # Your vendor has not defined POSIX macro ECONNREFUSED
  my @pairs = (ECONNREFUSED => 10061, # "Unknown Error" Special Win32 Response?
	       ENOTCONN     => 10057,
	       ECONNRESET   => 10054,
	       EINPROGRESS  => 10036,
	       EWOULDBLOCK  => 10035,
	  );
  while (my $name = shift @pairs) {
    my $value = shift @pairs;
    # When defined, these all are non-zero
    unless (eval $name) {
      no strict 'refs';
      *{$name} = defined prototype \&{$name} ? sub () {$value} : sub {$value};
    }
  }
};


sub pingecho
{
  my ($host,              # Name or IP number of host to ping
      $timeout            # Optional timeout in seconds
      ) = @_;
  my ($p);                # A ping object

  $p = Net::Ping->new("tcp", $timeout);
  $p->ping($host);        # Going out of scope closes the connection
}


sub new
{
  my ($this,
      $proto,             # Optional protocol to use for pinging
      $timeout,           # Optional timeout in seconds
      $data_size,         # Optional additional bytes of data
      $device,            # Optional device to use
      $tos,               # Optional ToS to set
      $ttl,               # Optional TTL to set
      $family,            # Optional address family (AF_INET)
      ) = @_;
  my  $class = ref($this) || $this;
  my  $self = {};
  my ($cnt,               # Count through data bytes
      $min_datasize       # Minimum data bytes required
      );

  bless($self, $class);
  if (ref $proto eq 'HASH') { # support named args
    for my $k (qw(proto timeout data_size device tos ttl family
                  gateway host port bind retrans pingstring source_verify
                  econnrefused dontfrag
                  IPV6_USE_MIN_MTU IPV6_RECVPATHMTU IPV6_HOPLIMIT))
    {
      if (exists $proto->{$k}) {
        $self->{$k} = $proto->{$k};
        # some are still globals
        if ($k eq 'pingstring') { $pingstring = $proto->{$k} }
        if ($k eq 'source_verify') { $source_verify = $proto->{$k} }
        # and some are local
        $timeout = $proto->{$k}   if ($k eq 'timeout');
        $data_size = $proto->{$k} if ($k eq 'data_size');
        $device = $proto->{$k}    if ($k eq 'device');
        $tos = $proto->{$k}       if ($k eq 'tos');
        $ttl = $proto->{$k}       if ($k eq 'ttl');
        $family = $proto->{$k}    if ($k eq 'family');
        delete $proto->{$k};
      }
    }
    if (%$proto) {
      croak("Invalid named argument: ",join(" ",keys (%$proto)));
    }
    $proto = $self->{'proto'};
  }

  $proto = $def_proto unless $proto;          # Determine the protocol
  croak('Protocol for ping must be "icmp", "icmpv6", "udp", "tcp", "syn", "stream" or "external"')
    unless $proto =~ m/^(icmp|icmpv6|udp|tcp|syn|stream|external)$/;
  $self->{proto} = $proto;

  $timeout = $def_timeout unless defined $timeout;    # Determine the timeout
  croak("Default timeout for ping must be greater than 0 seconds")
    if $timeout <= 0;
  $self->{timeout} = $timeout;

  $self->{device} = $device;

  $self->{tos} = $tos;

  if ($self->{'host'}) {
    my $host = $self->{'host'};
    my $ip = $self->_resolv($host) or
      carp("could not resolve host $host");
    $self->{host} = $ip;
    $self->{family} = $ip->{family};
  }

  if ($self->{bind}) {
    my $addr = $self->{bind};
    my $ip = $self->_resolv($addr)
      or carp("could not resolve local addr $addr");
    $self->{local_addr} = $ip;
  } else {
    $self->{local_addr} = undef;              # Don't bind by default
  }

  if ($self->{proto} eq 'icmp') {
    croak('TTL must be from 0 to 255')
      if ($ttl && ($ttl < 0 || $ttl > 255));
    $self->{ttl} = $ttl;
  }

  if ($family) {
    if ($family =~ $qr_family) {
      if ($family =~ $qr_family4) {
        $self->{family} = AF_INET;
      } else {
        $self->{family} = $AF_INET6;
      }
    } else {
      croak('Family must be "ipv4" or "ipv6"')
    }
  } else {
    if ($self->{proto} eq 'icmpv6') {
      $self->{family} = $AF_INET6;
    } else {
      $self->{family} = $def_family;
    }
  }

  $min_datasize = ($proto eq "udp") ? 1 : 0;  # Determine data size
  $data_size = $min_datasize unless defined($data_size) && $proto ne "tcp";
  # allow for fragmented packets if data_size>1472 (MTU 1500)
  croak("Data for ping must be from $min_datasize to $max_datasize bytes")
    if ($data_size < $min_datasize) || ($data_size > $max_datasize);
  $data_size-- if $self->{proto} eq "udp";  # We provide the first byte
  $self->{data_size} = $data_size;

  $self->{data} = "";                       # Construct data bytes
  for ($cnt = 0; $cnt < $self->{data_size}; $cnt++)
  {
    $self->{data} .= chr($cnt % 256);
  }

  # Default exponential backoff rate
  $self->{retrans} = $def_factor unless exists $self->{retrans};
  # Default Connection refused behavior
  $self->{econnrefused} = undef unless exists $self->{econnrefused};

  $self->{seq} = 0;                         # For counting packets
  if ($self->{proto} eq "udp")              # Open a socket
  {
    $self->{proto_num} = eval { (getprotobyname('udp'))[2] } ||
      croak("Can't udp protocol by name");
    $self->{port_num} = $self->{port}
      || (getservbyname('echo', 'udp'))[2]
      || croak("Can't get udp echo port by name");
    $self->{fh} = FileHandle->new();
    socket($self->{fh}, PF_INET, SOCK_DGRAM,
           $self->{proto_num}) ||
             croak("udp socket error - $!");
    $self->_setopts();
  }
  elsif ($self->{proto} eq "icmp")
  {
    croak("icmp ping requires root privilege") if !_isroot();
    $self->{proto_num} = eval { (getprotobyname('icmp'))[2] } ||
      croak("Can't get icmp protocol by name");
    $self->{pid} = $$ & 0xffff;           # Save lower 16 bits of pid
    $self->{fh} = FileHandle->new();
    socket($self->{fh}, PF_INET, SOCK_RAW, $self->{proto_num}) ||
      croak("icmp socket error - $!");
    $self->_setopts();
    if ($self->{'ttl'}) {
      setsockopt($self->{fh}, IPPROTO_IP, IP_TTL, pack("I*", $self->{'ttl'}))
        or croak "error configuring ttl to $self->{'ttl'} $!";
    }
  }
  elsif ($self->{proto} eq "icmpv6")
  {
    #croak("icmpv6 ping requires root privilege") if !_isroot();
    croak("Wrong family $self->{family} for icmpv6 protocol")
      if $self->{family} and $self->{family} != $AF_INET6;
    $self->{family} = $AF_INET6;
    $self->{proto_num} = eval { (getprotobyname('ipv6-icmp'))[2] } ||
      croak("Can't get ipv6-icmp protocol by name"); # 58
    $self->{pid} = $$ & 0xffff;           # Save lower 16 bits of pid
    $self->{fh} = FileHandle->new();
    socket($self->{fh}, $AF_INET6, SOCK_RAW, $self->{proto_num}) ||
      croak("icmp socket error - $!");
    $self->_setopts();
    if ($self->{'gateway'}) {
      my $g = $self->{gateway};
      my $ip = $self->_resolv($g)
        or croak("nonexistent gateway $g");
      $self->{family} eq $AF_INET6
        or croak("gateway requires the AF_INET6 family");
      $ip->{family} eq $AF_INET6
        or croak("gateway address needs to be IPv6");
      my $IPV6_NEXTHOP = eval { Socket::IPV6_NEXTHOP() } || 48; # IPV6_3542NEXTHOP, or 21
      setsockopt($self->{fh}, $IPPROTO_IPV6, $IPV6_NEXTHOP, _pack_sockaddr_in($ip))
        or croak "error configuring gateway to $g NEXTHOP $!";
    }
    if (exists $self->{IPV6_USE_MIN_MTU}) {
      my $IPV6_USE_MIN_MTU = eval { Socket::IPV6_USE_MIN_MTU() } || 42;
      setsockopt($self->{fh}, $IPPROTO_IPV6, $IPV6_USE_MIN_MTU,
                 pack("I*", $self->{'IPV6_USE_MIN_MT'}))
        or croak "error configuring IPV6_USE_MIN_MT} $!";
    }
    if (exists $self->{IPV6_RECVPATHMTU}) {
      my $IPV6_RECVPATHMTU = eval { Socket::IPV6_RECVPATHMTU() } || 43;
      setsockopt($self->{fh}, $IPPROTO_IPV6, $IPV6_RECVPATHMTU,
                 pack("I*", $self->{'RECVPATHMTU'}))
        or croak "error configuring IPV6_RECVPATHMTU $!";
    }
    if ($self->{'tos'}) {
      my $proto = $self->{family} == AF_INET ? IPPROTO_IP : $IPPROTO_IPV6;
      setsockopt($self->{fh}, $proto, IP_TOS, pack("I*", $self->{'tos'}))
        or croak "error configuring tos to $self->{'tos'} $!";
    }
    if ($self->{'ttl'}) {
      my $proto = $self->{family} == AF_INET ? IPPROTO_IP : $IPPROTO_IPV6;
      setsockopt($self->{fh}, $proto, IP_TTL, pack("I*", $self->{'ttl'}))
        or croak "error configuring ttl to $self->{'ttl'} $!";
    }
  }
  elsif ($self->{proto} eq "tcp" || $self->{proto} eq "stream")
  {
    $self->{proto_num} = eval { (getprotobyname('tcp'))[2] } ||
      croak("Can't get tcp protocol by name");
    $self->{port_num} = $self->{port}
      || (getservbyname('echo', 'tcp'))[2]
      ||  croak("Can't get tcp echo port by name");
    $self->{fh} = FileHandle->new();
  }
  elsif ($self->{proto} eq "syn")
  {
    $self->{proto_num} = eval { (getprotobyname('tcp'))[2] } ||
      croak("Can't get tcp protocol by name");
    $self->{port_num} = (getservbyname('echo', 'tcp'))[2] ||
      croak("Can't get tcp echo port by name");
    if ($syn_forking) {
      $self->{fork_rd} = FileHandle->new();
      $self->{fork_wr} = FileHandle->new();
      pipe($self->{fork_rd}, $self->{fork_wr});
      $self->{fh} = FileHandle->new();
      $self->{good} = {};
      $self->{bad} = {};
    } else {
      $self->{wbits} = "";
      $self->{bad} = {};
    }
    $self->{syn} = {};
    $self->{stop_time} = 0;
  }

  return($self);
}

sub bind
{
  my ($self,
      $local_addr         # Name or IP number of local interface
      ) = @_;
  my ($ip,                # Hash of addr (string), addr_in (packed), family
      $h		  # resolved hash
      );

  croak("Usage: \$p->bind(\$local_addr)") unless @_ == 2;
  croak("already bound") if defined($self->{local_addr}) &&
    ($self->{proto} eq "udp" || $self->{proto} eq "icmp");

  $ip = $self->_resolv($local_addr);
  carp("nonexistent local address $local_addr") unless defined($ip);
  $self->{local_addr} = $ip;

  if (($self->{proto} ne "udp") && 
      ($self->{proto} ne "icmp") && 
      ($self->{proto} ne "tcp") && 
      ($self->{proto} ne "syn"))
  {
    croak("Unknown protocol \"$self->{proto}\" in bind()");
  }

  return 1;
}

sub mselect
{
    if ($_[3] > 0 and $^O eq 'MSWin32') {
	# On windows, select() doesn't process the message loop,
	# but sleep() will, allowing alarm() to interrupt the latter.
	# So we chop up the timeout into smaller pieces and interleave
	# select() and sleep() calls.
	my $t = $_[3];
	my $gran = 0.5;  # polling granularity in seconds
	my @args = @_;
	while (1) {
	    $gran = $t if $gran > $t;
	    my $nfound = select($_[0], $_[1], $_[2], $gran);
	    undef $nfound if $nfound == -1;
	    $t -= $gran;
	    return $nfound if $nfound or !defined($nfound) or $t <= 0;

	    sleep(0);
	    ($_[0], $_[1], $_[2]) = @args;
	}
    }
    else {
	my $nfound = select($_[0], $_[1], $_[2], $_[3]);
	undef $nfound if $nfound == -1;
	return $nfound;
    }
}


sub source_verify
{
  my $self = shift;
  $source_verify = 1 unless defined
    ($source_verify = ((defined $self) && (ref $self)) ? shift() : $self);
}


sub service_check
{
  my $self = shift;
  $self->{econnrefused} = 1 unless defined
    ($self->{econnrefused} = shift());
}

sub tcp_service_check
{
  service_check(@_);
}


sub retrans
{
  my $self = shift;
  $self->{retrans} = shift;
}

sub _IsAdminUser {
  return unless $^O eq 'MSWin32' or $^O eq "cygwin";
  return unless eval { require Win32 };
  return unless defined &Win32::IsAdminUser;
  return Win32::IsAdminUser();
}

sub _isroot {
  if (($> and $^O ne 'VMS' and $^O ne 'cygwin')
    or (($^O eq 'MSWin32' or $^O eq 'cygwin')
        and !_IsAdminUser())
    or ($^O eq 'VMS'
        and (`write sys\$output f\$privilege("SYSPRV")` =~ m/FALSE/))) {
      return 0;
  }
  else {
    return 1;
  }
}


sub IPV6_REACHCONF
{
  my $self = shift;
  my $on = shift;
  if ($on) {
    my $reachconf = eval { Socket::IPV6_REACHCONF() };
    if (!$reachconf) {
      carp "IPV6_REACHCONF not supported on this platform";
      return 0;
    }
    if (!_isroot()) {
      carp "IPV6_REACHCONF requires root permissions";
      return 0;
    }
    $self->{IPV6_REACHCONF} = 1;
  }
  else {
    return $self->{IPV6_REACHCONF};
  }
}


sub IPV6_USE_MIN_MTU
{
  my $self = shift;
  my $on = shift;
  if (defined $on) {
    my $IPV6_USE_MIN_MTU = eval { Socket::IPV6_USE_MIN_MTU() } || 43;
    #if (!$IPV6_USE_MIN_MTU) {
    #  carp "IPV6_USE_MIN_MTU not supported on this platform";
    #  return 0;
    #}
    $self->{IPV6_USE_MIN_MTU} = $on ? 1 : 0;
    setsockopt($self->{fh}, $IPPROTO_IPV6, $IPV6_USE_MIN_MTU,
               pack("I*", $self->{'IPV6_USE_MIN_MT'}))
      or croak "error configuring IPV6_USE_MIN_MT} $!";
  }
  else {
    return $self->{IPV6_USE_MIN_MTU};
  }
}


sub IPV6_RECVPATHMTU
{
  my $self = shift;
  my $on = shift;
  if ($on) {
    my $IPV6_RECVPATHMTU = eval { Socket::IPV6_RECVPATHMTU() } || 43;
    #if (!$RECVPATHMTU) {
    #  carp "IPV6_RECVPATHMTU not supported on this platform";
    #  return 0;
    #}
    $self->{IPV6_RECVPATHMTU} = 1;
    setsockopt($self->{fh}, $IPPROTO_IPV6, $IPV6_RECVPATHMTU,
               pack("I*", $self->{'IPV6_RECVPATHMTU'}))
      or croak "error configuring IPV6_RECVPATHMTU} $!";
  }
  else {
    return $self->{IPV6_RECVPATHMTU};
  }
}


$hires = 1;
sub hires
{
  my $self = shift;
  $hires = 1 unless defined
    ($hires = ((defined $self) && (ref $self)) ? shift() : $self);
}

sub time
{
  return $hires ? Time::HiRes::time() : CORE::time();
}

sub socket_blocking_mode
{
  my ($self,
      $fh,              # the file handle whose flags are to be modified
      $block) = @_;     # if true then set the blocking
                        # mode (clear O_NONBLOCK), otherwise
                        # set the non-blocking mode (set O_NONBLOCK)

  my $flags;
  if ($^O eq 'MSWin32' || $^O eq 'VMS') {
      # FIONBIO enables non-blocking sockets on windows and vms.
      # FIONBIO is (0x80000000|(4<<16)|(ord('f')<<8)|126), as per winsock.h, ioctl.h
      my $f = 0x8004667e;
      my $v = pack("L", $block ? 0 : 1);
      ioctl($fh, $f, $v) or croak("ioctl failed: $!");
      return;
  }
  if ($flags = fcntl($fh, F_GETFL, 0)) {
    $flags = $block ? ($flags & ~O_NONBLOCK) : ($flags | O_NONBLOCK);
    if (!fcntl($fh, F_SETFL, $flags)) {
      croak("fcntl F_SETFL: $!");
    }
  } else {
    croak("fcntl F_GETFL: $!");
  }
}


sub ping
{
  my ($self,
      $host,              # Name or IP number of host to ping
      $timeout,           # Seconds after which ping times out
      $family,            # Address family
      ) = @_;
  my ($ip,                # Hash of addr (string), addr_in (packed), family
      $ret,               # The return value
      $ping_time,         # When ping began
      );

  $host = $self->{host} if !defined $host and $self->{host};
  croak("Usage: \$p->ping([ \$host [, \$timeout [, \$family]]])") if @_ > 4 or !$host;
  $timeout = $self->{timeout} unless $timeout;
  croak("Timeout must be greater than 0 seconds") if $timeout <= 0;

  if ($family) {
    if ($family =~ $qr_family) {
      if ($family =~ $qr_family4) {
        $self->{family_local} = AF_INET;
      } else {
        $self->{family_local} = $AF_INET6;
      }
    } else {
      croak('Family must be "ipv4" or "ipv6"')
    }
  } else {
    $self->{family_local} = $self->{family};
  }
  
  $ip = $self->_resolv($host);
  return () unless defined($ip);      # Does host exist?

  # Dispatch to the appropriate routine.
  $ping_time = &time();
  if ($self->{proto} eq "external") {
    $ret = $self->ping_external($ip, $timeout);
  }
  elsif ($self->{proto} eq "udp") {
    $ret = $self->ping_udp($ip, $timeout);
  }
  elsif ($self->{proto} eq "icmp") {
    $ret = $self->ping_icmp($ip, $timeout);
  }
  elsif ($self->{proto} eq "icmpv6") {
    $ret = $self->ping_icmpv6($ip, $timeout);
  }
  elsif ($self->{proto} eq "tcp") {
    $ret = $self->ping_tcp($ip, $timeout);
  }
  elsif ($self->{proto} eq "stream") {
    $ret = $self->ping_stream($ip, $timeout);
  }
  elsif ($self->{proto} eq "syn") {
    $ret = $self->ping_syn($host, $ip, $ping_time, $ping_time+$timeout);
  } else {
    croak("Unknown protocol \"$self->{proto}\" in ping()");
  }

  return wantarray ? ($ret, &time() - $ping_time, $self->ntop($ip)) : $ret;
}

sub ping_external {
  my ($self,
      $ip,                # Hash of addr (string), addr_in (packed), family
      $timeout,           # Seconds after which ping times out
      $family
     ) = @_;

  $ip = $self->{host} if !defined $ip and $self->{host};
  $timeout = $self->{timeout} if !defined $timeout and $self->{timeout};
  my @addr = exists $ip->{addr_in}
    ? ('ip' => $ip->{addr_in})
    : ('host' => $ip->{host});

  eval {
    local @INC = @INC;
    pop @INC if $INC[-1] eq '.';
    require Net::Ping::External;
  } or croak('Protocol "external" not supported on your system: Net::Ping::External not found');
  return Net::Ping::External::ping(@addr, timeout => $timeout,
                                   family => $family);
}

use constant SO_BINDTODEVICE  => 25;
use constant ICMP_ECHOREPLY   => 0;   # ICMP packet types
use constant ICMPv6_ECHOREPLY => 129; # ICMP packet types
use constant ICMP_UNREACHABLE => 3;   # ICMP packet types
use constant ICMPv6_UNREACHABLE => 1; # ICMP packet types
use constant ICMPv6_NI_REPLY => 140;  # ICMP packet types
use constant ICMP_ECHO        => 8;
use constant ICMPv6_ECHO      => 128;
use constant ICMP_TIME_EXCEEDED => 11; # ICMP packet types
use constant ICMP_PARAMETER_PROBLEM => 12; # ICMP packet types
use constant ICMP_TIMESTAMP   => 13;
use constant ICMP_TIMESTAMP_REPLY => 14;
use constant ICMP_STRUCT      => "C2 n3 A"; # Structure of a minimal ICMP packet
use constant ICMP_TIMESTAMP_STRUCT => "C2 n3 N3"; # Structure of a minimal timestamp ICMP packet
use constant SUBCODE          => 0; # No ICMP subcode for ECHO and ECHOREPLY
use constant ICMP_FLAGS       => 0; # No special flags for send or recv
use constant ICMP_PORT        => 0; # No port with ICMP
use constant IP_MTU_DISCOVER  => 10; # linux only

sub message_type
{
  my ($self,
      $type
      ) = @_;

  croak "Setting message type only supported on 'icmp' protocol"
    unless $self->{proto} eq 'icmp';

  return $self->{message_type} || 'echo'
    unless defined($type);

  croak "Supported icmp message type are limited to 'echo' and 'timestamp': '$type' not supported"
    unless $type =~ /^echo|timestamp$/i;

  $self->{message_type} = lc($type);
}

sub ping_icmp
{
  my ($self,
      $ip,                # Hash of addr (string), addr_in (packed), family
      $timeout            # Seconds after which ping times out
      ) = @_;

  my ($saddr,             # sockaddr_in with port and ip
      $checksum,          # Checksum of ICMP packet
      $msg,               # ICMP packet to send
      $len_msg,           # Length of $msg
      $rbits,             # Read bits, filehandles for reading
      $nfound,            # Number of ready filehandles found
      $finish_time,       # Time ping should be finished
      $done,              # set to 1 when we are done
      $ret,               # Return value
      $recv_msg,          # Received message including IP header
      $recv_msg_len,      # Length of recevied message, less any additional data
      $from_saddr,        # sockaddr_in of sender
      $from_port,         # Port packet was sent from
      $from_ip,           # Packed IP of sender
      $timestamp_msg,     # ICMP timestamp message type
      $from_type,         # ICMP type
      $from_subcode,      # ICMP subcode
      $from_chk,          # ICMP packet checksum
      $from_pid,          # ICMP packet id
      $from_seq,          # ICMP packet sequence
      $from_msg           # ICMP message
      );

  $ip = $self->{host} if !defined $ip and $self->{host};
  $timeout = $self->{timeout} if !defined $timeout and $self->{timeout};
  $timestamp_msg = $self->{message_type} && $self->{message_type} eq 'timestamp' ? 1 : 0;

  socket($self->{fh}, $ip->{family}, SOCK_RAW, $self->{proto_num}) ||
    croak("icmp socket error - $!");

  if (defined $self->{local_addr} &&
      !CORE::bind($self->{fh}, _pack_sockaddr_in(0, $self->{local_addr}))) {
    croak("icmp bind error - $!");
  }
  $self->_setopts();

  $self->{seq} = ($self->{seq} + 1) % 65536; # Increment sequence
  $checksum = 0;                          # No checksum for starters
  if ($ip->{family} == AF_INET) {
    if ($timestamp_msg) {
      $msg = pack(ICMP_TIMESTAMP_STRUCT, ICMP_TIMESTAMP, SUBCODE,
                  $checksum, $self->{pid}, $self->{seq}, 0, 0, 0);
    } else {
      $msg = pack(ICMP_STRUCT . $self->{data_size}, ICMP_ECHO, SUBCODE,
                  $checksum, $self->{pid}, $self->{seq}, $self->{data});
    }
  } else {
                                          # how to get SRC
    my $pseudo_header = pack('a16a16Nnn', $ip->{addr_in}, $ip->{addr_in}, 8+length($self->{data}), 0, 0x003a);
    $msg = pack(ICMP_STRUCT . $self->{data_size}, ICMPv6_ECHO, SUBCODE,
                $checksum, $self->{pid}, $self->{seq}, $self->{data});
    $msg = $pseudo_header.$msg
  }
  $checksum = Net::Ping->checksum($msg);
  if ($ip->{family} == AF_INET) {
    if ($timestamp_msg) {
      $msg = pack(ICMP_TIMESTAMP_STRUCT, ICMP_TIMESTAMP, SUBCODE,
                  $checksum, $self->{pid}, $self->{seq}, 0, 0, 0);
    } else {
      $msg = pack(ICMP_STRUCT . $self->{data_size}, ICMP_ECHO, SUBCODE,
                  $checksum, $self->{pid}, $self->{seq}, $self->{data});
    }
  } else {
    $msg = pack(ICMP_STRUCT . $self->{data_size}, ICMPv6_ECHO, SUBCODE,
                $checksum, $self->{pid}, $self->{seq}, $self->{data});
  }
  $len_msg = length($msg);
  $saddr = _pack_sockaddr_in(ICMP_PORT, $ip);
  $self->{from_ip} = undef;
  $self->{from_type} = undef;
  $self->{from_subcode} = undef;
  send($self->{fh}, $msg, ICMP_FLAGS, $saddr); # Send the message

  $rbits = "";
  vec($rbits, $self->{fh}->fileno(), 1) = 1;
  $ret = 0;
  $done = 0;
  $finish_time = &time() + $timeout;      # Must be done by this time
  while (!$done && $timeout > 0)          # Keep trying if we have time
  {
    $nfound = mselect((my $rout=$rbits), undef, undef, $timeout); # Wait for packet
    $timeout = $finish_time - &time();    # Get remaining time
    if (!defined($nfound))                # Hmm, a strange error
    {
      $ret = undef;
      $done = 1;
    }
    elsif ($nfound)                     # Got a packet from somewhere
    {
      $recv_msg = "";
      $from_pid = -1;
      $from_seq = -1;
      $from_saddr = recv($self->{fh}, $recv_msg, 1500, ICMP_FLAGS);
      $recv_msg_len = length($recv_msg) - length($self->{data});
      ($from_port, $from_ip) = _unpack_sockaddr_in($from_saddr, $ip->{family});
      # ICMP echo includes the header and ICMPv6 doesn't.
      # IPv4 length($recv_msg) is 28 (20 header + 8 payload)
      # while IPv6 length is only 8 (sans header).
      my $off = ($ip->{family} == AF_INET) ? 20 : 0; # payload offset
      ($from_type, $from_subcode) = unpack("C2", substr($recv_msg, $off, 2));
      if ($from_type == ICMP_TIMESTAMP_REPLY) {
        ($from_pid, $from_seq) = unpack("n3", substr($recv_msg, $off + 4, 4))
          if length $recv_msg >= $off + 8;
      } elsif ($from_type == ICMP_ECHOREPLY || $from_type == ICMPv6_ECHOREPLY) {
        #warn "ICMP_ECHOREPLY: ", $ip->{family}, " ",$recv_msg, ":", length($recv_msg);
        ($from_pid, $from_seq) = unpack("n2", substr($recv_msg, $off + 4, 4))
          if $recv_msg_len == $off + 8;
      } elsif ($from_type == ICMPv6_NI_REPLY) {
        ($from_pid, $from_seq) = unpack("n2", substr($recv_msg, 4, 4))
          if ($ip->{family} == $AF_INET6 && length $recv_msg == 8);
      } else {
        #warn "ICMP: ", $from_type, " ",$ip->{family}, " ",$recv_msg, ":", length($recv_msg);
        ($from_pid, $from_seq) = unpack("n2", substr($recv_msg, $off + 32, 4))
          if length $recv_msg >= $off + 36;
      }
      $self->{from_ip} = $from_ip;
      $self->{from_type} = $from_type;
      $self->{from_subcode} = $from_subcode;
      next if ($from_pid != $self->{pid});
      next if ($from_seq != $self->{seq});
      if (! $source_verify || ($self->ntop($from_ip) eq $self->ntop($ip))) { # Does the packet check out?
        if (!$timestamp_msg && (($from_type == ICMP_ECHOREPLY) || ($from_type == ICMPv6_ECHOREPLY))) {
          $ret = 1;
          $done = 1;
        } elsif ($timestamp_msg && $from_type == ICMP_TIMESTAMP_REPLY) {
          $ret = 1;
          $done = 1;
        } elsif (($from_type == ICMP_UNREACHABLE) || ($from_type == ICMPv6_UNREACHABLE)) {
          $done = 1;
        } elsif ($from_type == ICMP_TIME_EXCEEDED) {
          $ret = 0;
          $done = 1;
        }
      }
    } else {     # Oops, timed out
      $done = 1;
    }
  }
  return $ret;
}

sub ping_icmpv6
{
  shift->ping_icmp(@_);
}

sub icmp_result {
  my ($self) = @_;
  my $addr = $self->{from_ip} || "";
  $addr = "\0\0\0\0" unless 4 == length $addr;
  return ($self->ntop($addr),($self->{from_type} || 0), ($self->{from_subcode} || 0));
}


sub checksum
{
  my ($class,
      $msg            # The message to checksum
      ) = @_;
  my ($len_msg,       # Length of the message
      $num_short,     # The number of short words in the message
      $short,         # One short word
      $chk            # The checksum
      );

  $len_msg = length($msg);
  $num_short = int($len_msg / 2);
  $chk = 0;
  foreach $short (unpack("n$num_short", $msg))
  {
    $chk += $short;
  }                                           # Add the odd byte in
  $chk += (unpack("C", substr($msg, $len_msg - 1, 1)) << 8) if $len_msg % 2;
  $chk = ($chk >> 16) + ($chk & 0xffff);      # Fold high into low
  return(~(($chk >> 16) + $chk) & 0xffff);    # Again and complement
}



sub ping_tcp
{
  my ($self,
      $ip,                # Hash of addr (string), addr_in (packed), family
      $timeout            # Seconds after which ping times out
      ) = @_;
  my ($ret                # The return value
      );

  $ip = $self->{host} if !defined $ip and $self->{host};
  $timeout = $self->{timeout} if !defined $timeout and $self->{timeout};

  $! = 0;
  $ret = $self -> tcp_connect( $ip, $timeout);
  if (!$self->{econnrefused} &&
      $! == ECONNREFUSED) {
    $ret = 1;  # "Connection refused" means reachable
  }
  $self->{fh}->close();
  return $ret;
}

sub tcp_connect
{
  my ($self,
      $ip,                # Hash of addr (string), addr_in (packed), family
      $timeout            # Seconds after which connect times out
      ) = @_;
  my ($saddr);            # Packed IP and Port

  $ip = $self->{host} if !defined $ip and $self->{host};
  $timeout = $self->{timeout} if !defined $timeout and $self->{timeout};

  $saddr = _pack_sockaddr_in($self->{port_num}, $ip);

  my $ret = 0;            # Default to unreachable

  my $do_socket = sub {
    socket($self->{fh}, $ip->{family}, SOCK_STREAM, $self->{proto_num}) ||
      croak("tcp socket error - $!");
    if (defined $self->{local_addr} &&
        !CORE::bind($self->{fh}, _pack_sockaddr_in(0, $self->{local_addr}))) {
      croak("tcp bind error - $!");
    }
    $self->_setopts();
  };
  my $do_connect = sub {
    $self->{ip} = $ip->{addr_in};
    # ECONNREFUSED is 10061 on MSWin32. If we pass it as child error through $?,
    # we'll get (10061 & 255) = 77, so we cannot check it in the parent process.
    return ($ret = connect($self->{fh}, $saddr) || ($! == ECONNREFUSED && !$self->{econnrefused}));
  };
  my $do_connect_nb = sub {
    # Set O_NONBLOCK property on filehandle
    $self->socket_blocking_mode($self->{fh}, 0);

    # start the connection attempt
    if (!connect($self->{fh}, $saddr)) {
      if ($! == ECONNREFUSED) {
        $ret = 1 unless $self->{econnrefused};
      } elsif ($! != EINPROGRESS && ($^O ne 'MSWin32' || $! != EWOULDBLOCK)) {
        # EINPROGRESS is the expected error code after a connect()
        # on a non-blocking socket.  But if the kernel immediately
        # determined that this connect() will never work,
        # Simply respond with "unreachable" status.
        # (This can occur on some platforms with errno
        # EHOSTUNREACH or ENETUNREACH.)
        return 0;
      } else {
        # Got the expected EINPROGRESS.
        # Just wait for connection completion...
        my ($wbits, $wout, $wexc);
        $wout = $wexc = $wbits = "";
        vec($wbits, $self->{fh}->fileno, 1) = 1;

        my $nfound = mselect(undef,
			    ($wout = $wbits),
			    ($^O eq 'MSWin32' ? ($wexc = $wbits) : undef),
			    $timeout);
        warn("select: $!") unless defined $nfound;

        if ($nfound && vec($wout, $self->{fh}->fileno, 1)) {
          # the socket is ready for writing so the connection
          # attempt completed. test whether the connection
          # attempt was successful or not

          if (getpeername($self->{fh})) {
            # Connection established to remote host
            $ret = 1;
          } else {
            # TCP ACK will never come from this host
            # because there was an error connecting.

            # This should set $! to the correct error.
            my $char;
            sysread($self->{fh},$char,1);
            $! = ECONNREFUSED if ($! == EAGAIN && $^O =~ /cygwin/i);

            $ret = 1 if (!$self->{econnrefused}
                         && $! == ECONNREFUSED);
          }
        } else {
          # the connection attempt timed out (or there were connect
	  # errors on Windows)
	  if ($^O =~ 'MSWin32') {
	      # If the connect will fail on a non-blocking socket,
	      # winsock reports ECONNREFUSED as an exception, and we
	      # need to fetch the socket-level error code via getsockopt()
	      # instead of using the thread-level error code that is in $!.
	      if ($nfound && vec($wexc, $self->{fh}->fileno, 1)) {
		  $! = unpack("i", getsockopt($self->{fh}, SOL_SOCKET,
			                      SO_ERROR));
	      }
	  }
        }
      }
    } else {
      # Connection established to remote host
      $ret = 1;
    }

    # Unset O_NONBLOCK property on filehandle
    $self->socket_blocking_mode($self->{fh}, 1);
    $self->{ip} = $ip->{addr_in};
    return $ret;
  };

  if ($syn_forking) {
    # Buggy Winsock API doesn't allow nonblocking connect.
    # Hence, if our OS is Windows, we need to create a separate
    # process to do the blocking connect attempt.
    # XXX Above comments are not true at least for Win2K, where
    # nonblocking connect works.

    $| = 1; # Clear buffer prior to fork to prevent duplicate flushing.
    $self->{'tcp_chld'} = fork;
    if (!$self->{'tcp_chld'}) {
      if (!defined $self->{'tcp_chld'}) {
        # Fork did not work
        warn "Fork error: $!";
        return 0;
      }
      &{ $do_socket }();

      # Try a slow blocking connect() call
      # and report the status to the parent.
      if ( &{ $do_connect }() ) {
        $self->{fh}->close();
        # No error
        exit 0;
      } else {
        # Pass the error status to the parent
        # Make sure that $! <= 255
        exit($! <= 255 ? $! : 255);
      }
    }

    &{ $do_socket }();

    my $patience = &time() + $timeout;

    my ($child, $child_errno);
    $? = 0; $child_errno = 0;
    # Wait up to the timeout
    # And clean off the zombie
    do {
      $child = waitpid($self->{'tcp_chld'}, &WNOHANG());
      $child_errno = $? >> 8;
      select(undef, undef, undef, 0.1);
    } while &time() < $patience && $child != $self->{'tcp_chld'};

    if ($child == $self->{'tcp_chld'}) {
      if ($self->{proto} eq "stream") {
        # We need the socket connected here, in parent
        # Should be safe to connect because the child finished
        # within the timeout
        &{ $do_connect }();
      }
      # $ret cannot be set by the child process
      $ret = !$child_errno;
    } else {
      # Time must have run out.
      # Put that choking client out of its misery
      kill "KILL", $self->{'tcp_chld'};
      # Clean off the zombie
      waitpid($self->{'tcp_chld'}, 0);
      $ret = 0;
    }
    delete $self->{'tcp_chld'};
    $! = $child_errno;
  } else {
    # Otherwise don't waste the resources to fork

    &{ $do_socket }();

    &{ $do_connect_nb }();
  }

  return $ret;
}

sub DESTROY {
  my $self = shift;
  if ($self->{'proto'} && ($self->{'proto'} eq 'tcp') && $self->{'tcp_chld'}) {
    # Put that choking client out of its misery
    kill "KILL", $self->{'tcp_chld'};
    # Clean off the zombie
    waitpid($self->{'tcp_chld'}, 0);
  }
}

sub tcp_echo
{
  my ($self, $timeout, $pingstring) = @_;

  $timeout = $self->{timeout} if !defined $timeout and $self->{timeout};
  $pingstring = $self->{pingstring} if !defined $pingstring and $self->{pingstring};

  my $ret = undef;
  my $time = &time();
  my $wrstr = $pingstring;
  my $rdstr = "";

  eval <<'EOM';
    do {
      my $rin = "";
      vec($rin, $self->{fh}->fileno(), 1) = 1;

      my $rout = undef;
      if($wrstr) {
        $rout = "";
        vec($rout, $self->{fh}->fileno(), 1) = 1;
      }

      if(mselect($rin, $rout, undef, ($time + $timeout) - &time())) {

        if($rout && vec($rout,$self->{fh}->fileno(),1)) {
          my $num = syswrite($self->{fh}, $wrstr, length $wrstr);
          if($num) {
            # If it was a partial write, update and try again.
            $wrstr = substr($wrstr,$num);
          } else {
            # There was an error.
            $ret = 0;
          }
        }

        if(vec($rin,$self->{fh}->fileno(),1)) {
          my $reply;
          if(sysread($self->{fh},$reply,length($pingstring)-length($rdstr))) {
            $rdstr .= $reply;
            $ret = 1 if $rdstr eq $pingstring;
          } else {
            # There was an error.
            $ret = 0;
          }
        }

      }
    } until &time() > ($time + $timeout) || defined($ret);
EOM

  return $ret;
}


sub ping_stream
{
  my ($self,
      $ip,                # Hash of addr (string), addr_in (packed), family
      $timeout            # Seconds after which ping times out
      ) = @_;

  # Open the stream if it's not already open
  if(!defined $self->{fh}->fileno()) {
    $self->tcp_connect($ip, $timeout) or return 0;
  }

  croak "tried to switch servers while stream pinging"
    if $self->{ip} ne $ip->{addr_in};

  return $self->tcp_echo($timeout, $pingstring);
}


sub open
{
  my ($self,
      $host,              # Host or IP address
      $timeout,           # Seconds after which open times out
      $family
      ) = @_;
  my $ip;                 # Hash of addr (string), addr_in (packed), family
  $host = $self->{host} unless defined $host;

  if ($family) {
    if ($family =~ $qr_family) {
      if ($family =~ $qr_family4) {
        $self->{family_local} = AF_INET;
      } else {
        $self->{family_local} = $AF_INET6;
      }
    } else {
      croak('Family must be "ipv4" or "ipv6"')
    }
  } else {
    $self->{family_local} = $self->{family};
  }

  $timeout = $self->{timeout} unless $timeout;
  $ip = $self->_resolv($host);

  if ($self->{proto} eq "stream") {
    if (defined($self->{fh}->fileno())) {
      croak("socket is already open");
    } else {
      return () unless $ip;
      $self->tcp_connect($ip, $timeout);
    }
  }
}

sub _dontfrag {
  my $self = shift;
  # bsd solaris
  my $IP_DONTFRAG = eval { Socket::IP_DONTFRAG() };
  if ($IP_DONTFRAG) {
    my $i = 1;
    setsockopt($self->{fh}, IPPROTO_IP, $IP_DONTFRAG, pack("I*", $i))
      or croak "error configuring IP_DONTFRAG $!";
    # Linux needs more: Path MTU Discovery as defined in RFC 1191
    # For non SOCK_STREAM sockets it is the user's responsibility to packetize
    # the data in MTU sized chunks and to do the retransmits if necessary.
    # The kernel will reject packets that are bigger than the known path
    # MTU if this flag is set (with EMSGSIZE).
    if ($^O eq 'linux') {
      my $i = 2; # IP_PMTUDISC_DO
      setsockopt($self->{fh}, IPPROTO_IP, IP_MTU_DISCOVER, pack("I*", $i))
        or croak "error configuring IP_MTU_DISCOVER $!";
    }
  }
}

sub _setopts {
  my $self = shift;
  if ($self->{'device'}) {
    setsockopt($self->{fh}, SOL_SOCKET, SO_BINDTODEVICE, pack("Z*", $self->{'device'}))
      or croak "error binding to device $self->{'device'} $!";
  }
  if ($self->{'tos'}) { # need to re-apply ToS (RT #6706)
    setsockopt($self->{fh}, IPPROTO_IP, IP_TOS, pack("I*", $self->{'tos'}))
      or croak "error applying tos to $self->{'tos'} $!";
  }
  if ($self->{'dontfrag'}) {
    $self->_dontfrag;
  }
}  



use constant UDP_FLAGS => 0; # Nothing special on send or recv
sub ping_udp
{
  my ($self,
      $ip,                # Hash of addr (string), addr_in (packed), family
      $timeout            # Seconds after which ping times out
      ) = @_;

  my ($saddr,             # sockaddr_in with port and ip
      $ret,               # The return value
      $msg,               # Message to be echoed
      $finish_time,       # Time ping should be finished
      $flush,             # Whether socket needs to be disconnected
      $connect,           # Whether socket needs to be connected
      $done,              # Set to 1 when we are done pinging
      $rbits,             # Read bits, filehandles for reading
      $nfound,            # Number of ready filehandles found
      $from_saddr,        # sockaddr_in of sender
      $from_msg,          # Characters echoed by $host
      $from_port,         # Port message was echoed from
      $from_ip            # Packed IP number of sender
      );

  $saddr = _pack_sockaddr_in($self->{port_num}, $ip);
  $self->{seq} = ($self->{seq} + 1) % 256;    # Increment sequence
  $msg = chr($self->{seq}) . $self->{data};   # Add data if any

  socket($self->{fh}, $ip->{family}, SOCK_DGRAM,
         $self->{proto_num}) ||
           croak("udp socket error - $!");

  if (defined $self->{local_addr} &&
      !CORE::bind($self->{fh}, _pack_sockaddr_in(0, $self->{local_addr}))) {
    croak("udp bind error - $!");
  }

  $self->_setopts();

  if ($self->{connected}) {
    if ($self->{connected} ne $saddr) {
      # Still connected to wrong destination.
      # Need to flush out the old one.
      $flush = 1;
    }
  } else {
    # Not connected yet.
    # Need to connect() before send()
    $connect = 1;
  }

  # Have to connect() and send() instead of sendto()
  # in order to pick up on the ECONNREFUSED setting
  # from recv() or double send() errno as utilized in
  # the concept by rdw @ perlmonks.  See:
  # http://perlmonks.thepen.com/42898.html
  if ($flush) {
    # Need to socket() again to flush the descriptor
    # This will disconnect from the old saddr.
    socket($self->{fh}, $ip->{family}, SOCK_DGRAM,
           $self->{proto_num});
    $self->_setopts();
  }
  # Connect the socket if it isn't already connected
  # to the right destination.
  if ($flush || $connect) {
    connect($self->{fh}, $saddr);               # Tie destination to socket
    $self->{connected} = $saddr;
  }
  send($self->{fh}, $msg, UDP_FLAGS);           # Send it

  $rbits = "";
  vec($rbits, $self->{fh}->fileno(), 1) = 1;
  $ret = 0;                   # Default to unreachable
  $done = 0;
  my $retrans = 0.01;
  my $factor = $self->{retrans};
  $finish_time = &time() + $timeout;       # Ping needs to be done by then
  while (!$done && $timeout > 0)
  {
    if ($factor > 1)
    {
      $timeout = $retrans if $timeout > $retrans;
      $retrans*= $factor; # Exponential backoff
    }
    $nfound  = mselect((my $rout=$rbits), undef, undef, $timeout); # Wait for response
    my $why = $!;
    $timeout = $finish_time - &time();   # Get remaining time

    if (!defined($nfound))  # Hmm, a strange error
    {
      $ret = undef;
      $done = 1;
    }
    elsif ($nfound)         # A packet is waiting
    {
      $from_msg = "";
      $from_saddr = recv($self->{fh}, $from_msg, 1500, UDP_FLAGS);
      if (!$from_saddr) {
        # For example an unreachable host will make recv() fail.
        if (!$self->{econnrefused} &&
            ($! == ECONNREFUSED ||
             $! == ECONNRESET)) {
          # "Connection refused" means reachable
          # Good, continue
          $ret = 1;
        }
        $done = 1;
      } else {
        ($from_port, $from_ip) = _unpack_sockaddr_in($from_saddr, $ip->{family});
        my $addr_in = ref($ip) eq "HASH" ? $ip->{addr_in} : $ip;
        if (!$source_verify ||
            (($from_ip eq $addr_in) &&        # Does the packet check out?
             ($from_port == $self->{port_num}) &&
             ($from_msg eq $msg)))
        {
          $ret = 1;       # It's a winner
          $done = 1;
        }
      }
    }
    elsif ($timeout <= 0)              # Oops, timed out
    {
      $done = 1;
    }
    else
    {
      # Send another in case the last one dropped
      if (send($self->{fh}, $msg, UDP_FLAGS)) {
        # Another send worked?  The previous udp packet
        # must have gotten lost or is still in transit.
        # Hopefully this new packet will arrive safely.
      } else {
        if (!$self->{econnrefused} &&
            $! == ECONNREFUSED) {
          # "Connection refused" means reachable
          # Good, continue
          $ret = 1;
        }
        $done = 1;
      }
    }
  }
  return $ret;
}

sub ping_syn
{
  my $self = shift;
  my $host = shift;
  my $ip = shift;
  my $start_time = shift;
  my $stop_time = shift;

  if ($syn_forking) {
    return $self->ping_syn_fork($host, $ip, $start_time, $stop_time);
  }

  my $fh = FileHandle->new();
  my $saddr = _pack_sockaddr_in($self->{port_num}, $ip);

  # Create TCP socket
  if (!socket ($fh, $ip->{family}, SOCK_STREAM, $self->{proto_num})) {
    croak("tcp socket error - $!");
  }

  if (defined $self->{local_addr} &&
      !CORE::bind($fh, _pack_sockaddr_in(0, $self->{local_addr}))) {
    croak("tcp bind error - $!");
  }

  $self->_setopts();
  # Set O_NONBLOCK property on filehandle
  $self->socket_blocking_mode($fh, 0);

  # Attempt the non-blocking connect
  # by just sending the TCP SYN packet
  if (connect($fh, $saddr)) {
    # Non-blocking, yet still connected?
    # Must have connected very quickly,
    # or else it wasn't very non-blocking.
    #warn "WARNING: Nonblocking connect connected anyway? ($^O)";
  } else {
    # Error occurred connecting.
    if ($! == EINPROGRESS || ($^O eq 'MSWin32' && $! == EWOULDBLOCK)) {
      # The connection is just still in progress.
      # This is the expected condition.
    } else {
      # Just save the error and continue on.
      # The ack() can check the status later.
      $self->{bad}->{$host} = $!;
    }
  }

  my $entry = [ $host, $ip, $fh, $start_time, $stop_time, $self->{port_num} ];
  $self->{syn}->{$fh->fileno} = $entry;
  if ($self->{stop_time} < $stop_time) {
    $self->{stop_time} = $stop_time;
  }
  vec($self->{wbits}, $fh->fileno, 1) = 1;

  return 1;
}

sub ping_syn_fork {
  my ($self, $host, $ip, $start_time, $stop_time) = @_;

  # Buggy Winsock API doesn't allow nonblocking connect.
  # Hence, if our OS is Windows, we need to create a separate
  # process to do the blocking connect attempt.
  my $pid = fork();
  if (defined $pid) {
    if ($pid) {
      # Parent process
      my $entry = [ $host, $ip, $pid, $start_time, $stop_time ];
      $self->{syn}->{$pid} = $entry;
      if ($self->{stop_time} < $stop_time) {
        $self->{stop_time} = $stop_time;
      }
    } else {
      # Child process
      my $saddr = _pack_sockaddr_in($self->{port_num}, $ip);

      # Create TCP socket
      if (!socket ($self->{fh}, $ip->{family}, SOCK_STREAM, $self->{proto_num})) {
        croak("tcp socket error - $!");
      }

      if (defined $self->{local_addr} &&
          !CORE::bind($self->{fh}, _pack_sockaddr_in(0, $self->{local_addr}))) {
        croak("tcp bind error - $!");
      }

      $self->_setopts();

      $!=0;
      # Try to connect (could take a long time)
      connect($self->{fh}, $saddr);
      # Notify parent of connect error status
      my $err = $!+0;
      my $wrstr = "$$ $err";
      # Force to 16 chars including \n
      $wrstr .= " "x(15 - length $wrstr). "\n";
      syswrite($self->{fork_wr}, $wrstr, length $wrstr);
      exit;
    }
  } else {
    # fork() failed?
    die "fork: $!";
  }
  return 1;
}

sub ack
{
  my $self = shift;

  if ($self->{proto} eq "syn") {
    if ($syn_forking) {
      my @answer = $self->ack_unfork(shift);
      return wantarray ? @answer : $answer[0];
    }
    my $wbits = "";
    my $stop_time = 0;
    if (my $host = shift or $self->{host}) {
      # Host passed as arg or as option to new
      $host = $self->{host} unless defined $host;
      if (exists $self->{bad}->{$host}) {
        if (!$self->{econnrefused} &&
            $self->{bad}->{ $host } &&
            (($! = ECONNREFUSED)>0) &&
            $self->{bad}->{ $host } eq "$!") {
          # "Connection refused" means reachable
          # Good, continue
        } else {
          # ECONNREFUSED means no good
          return ();
        }
      }
      my $host_fd = undef;
      foreach my $fd (keys %{ $self->{syn} }) {
        my $entry = $self->{syn}->{$fd};
        if ($entry->[0] eq $host) {
          $host_fd = $fd;
          $stop_time = $entry->[4]
            || croak("Corrupted SYN entry for [$host]");
          last;
        }
      }
      croak("ack called on [$host] without calling ping first!")
        unless defined $host_fd;
      vec($wbits, $host_fd, 1) = 1;
    } else {
      # No $host passed so scan all hosts
      # Use the latest stop_time
      $stop_time = $self->{stop_time};
      # Use all the bits
      $wbits = $self->{wbits};
    }

    while ($wbits !~ /^\0*\z/) {
      my $timeout = $stop_time - &time();
      # Force a minimum of 10 ms timeout.
      $timeout = 0.01 if $timeout <= 0.01;

      my $winner_fd = undef;
      my $wout = $wbits;
      my $fd = 0;
      # Do "bad" fds from $wbits first
      while ($wout !~ /^\0*\z/) {
        if (vec($wout, $fd, 1)) {
          # Wipe it from future scanning.
          vec($wout, $fd, 1) = 0;
          if (my $entry = $self->{syn}->{$fd}) {
            if ($self->{bad}->{ $entry->[0] }) {
              $winner_fd = $fd;
              last;
            }
          }
        }
        $fd++;
      }

      if (defined($winner_fd) or my $nfound = mselect(undef, ($wout=$wbits), undef, $timeout)) {
        if (defined $winner_fd) {
          $fd = $winner_fd;
        } else {
          # Done waiting for one of the ACKs
          $fd = 0;
          # Determine which one
          while ($wout !~ /^\0*\z/ &&
                 !vec($wout, $fd, 1)) {
            $fd++;
          }
        }
        if (my $entry = $self->{syn}->{$fd}) {
          # Wipe it from future scanning.
          delete $self->{syn}->{$fd};
          vec($self->{wbits}, $fd, 1) = 0;
          vec($wbits, $fd, 1) = 0;
          if (!$self->{econnrefused} &&
              $self->{bad}->{ $entry->[0] } &&
              (($! = ECONNREFUSED)>0) &&
              $self->{bad}->{ $entry->[0] } eq "$!") {
            # "Connection refused" means reachable
            # Good, continue
          } elsif (getpeername($entry->[2])) {
            # Connection established to remote host
            # Good, continue
          } else {
            # TCP ACK will never come from this host
            # because there was an error connecting.

            # This should set $! to the correct error.
            my $char;
            sysread($entry->[2],$char,1);
            # Store the excuse why the connection failed.
            $self->{bad}->{$entry->[0]} = $!;
            if (!$self->{econnrefused} &&
                (($! == ECONNREFUSED) ||
                 ($! == EAGAIN && $^O =~ /cygwin/i))) {
              # "Connection refused" means reachable
              # Good, continue
            } else {
              # No good, try the next socket...
              next;
            }
          }
          # Everything passed okay, return the answer
          return wantarray ?
            ($entry->[0], &time() - $entry->[3], $self->ntop($entry->[1]), $entry->[5])
            : $entry->[0];
        } else {
          warn "Corrupted SYN entry: unknown fd [$fd] ready!";
          vec($wbits, $fd, 1) = 0;
          vec($self->{wbits}, $fd, 1) = 0;
        }
      } elsif (defined $nfound) {
        # Timed out waiting for ACK
        foreach my $fd (keys %{ $self->{syn} }) {
          if (vec($wbits, $fd, 1)) {
            my $entry = $self->{syn}->{$fd};
            $self->{bad}->{$entry->[0]} = "Timed out";
            vec($wbits, $fd, 1) = 0;
            vec($self->{wbits}, $fd, 1) = 0;
            delete $self->{syn}->{$fd};
          }
        }
      } else {
        # Weird error occurred with select()
        warn("select: $!");
        $self->{syn} = {};
        $wbits = "";
      }
    }
  }
  return ();
}

sub ack_unfork {
  my ($self,$host) = @_;
  my $stop_time = $self->{stop_time};
  if ($host) {
    # Host passed as arg
    if (my $entry = $self->{good}->{$host}) {
      delete $self->{good}->{$host};
      return ($entry->[0], &time() - $entry->[3], $self->ntop($entry->[1]));
    }
  }

  my $rbits = "";
  my $timeout;

  if (keys %{ $self->{syn} }) {
    # Scan all hosts that are left
    vec($rbits, fileno($self->{fork_rd}), 1) = 1;
    $timeout = $stop_time - &time();
    # Force a minimum of 10 ms timeout.
    $timeout = 0.01 if $timeout < 0.01;
  } else {
    # No hosts left to wait for
    $timeout = 0;
  }

  if ($timeout > 0) {
    my $nfound;
    while ( keys %{ $self->{syn} } and
           $nfound = mselect((my $rout=$rbits), undef, undef, $timeout)) {
      # Done waiting for one of the ACKs
      if (!sysread($self->{fork_rd}, $_, 16)) {
        # Socket closed, which means all children are done.
        return ();
      }
      my ($pid, $how) = split;
      if ($pid) {
        # Flush the zombie
        waitpid($pid, 0);
        if (my $entry = $self->{syn}->{$pid}) {
          # Connection attempt to remote host is done
          delete $self->{syn}->{$pid};
          if (!$how || # If there was no error connecting
              (!$self->{econnrefused} &&
               $how == ECONNREFUSED)) {  # "Connection refused" means reachable
            if ($host && $entry->[0] ne $host) {
              # A good connection, but not the host we need.
              # Move it from the "syn" hash to the "good" hash.
              $self->{good}->{$entry->[0]} = $entry;
              # And wait for the next winner
              next;
            }
            return ($entry->[0], &time() - $entry->[3], $self->ntop($entry->[1]));
          }
        } else {
          # Should never happen
          die "Unknown ping from pid [$pid]";
        }
      } else {
        die "Empty response from status socket?";
      }
    }
    if (defined $nfound) {
      # Timed out waiting for ACK status
    } else {
      # Weird error occurred with select()
      warn("select: $!");
    }
  }
  if (my @synners = keys %{ $self->{syn} }) {
    # Kill all the synners
    kill 9, @synners;
    foreach my $pid (@synners) {
      # Wait for the deaths to finish
      # Then flush off the zombie
      waitpid($pid, 0);
    }
  }
  $self->{syn} = {};
  return ();
}

sub nack {
  my $self = shift;
  my $host = shift || croak('Usage> nack($failed_ack_host)');
  return $self->{bad}->{$host} || undef;
}


sub close
{
  my ($self) = @_;

  if ($self->{proto} eq "syn") {
    delete $self->{syn};
  } elsif ($self->{proto} eq "tcp") {
    # The connection will already be closed
  } elsif ($self->{proto} eq "external") {
    # Nothing to close
  } else {
    $self->{fh}->close();
  }
}

sub port_number {
   my $self = shift;
   if(@_) {
       $self->{port_num} = shift @_;
       $self->service_check(1);
   }
   return $self->{port_num};
}

sub ntop {
    my($self, $ip) = @_;

    # Vista doesn't define a inet_ntop.  It has InetNtop instead.
    # Not following ANSI... priceless.  getnameinfo() is defined
    # for Windows 2000 and later, so that may be the choice.

    # Any port will work, even undef, but this will work for now.
    # Socket warns when undef is passed in, but it still works.
    my $port = getservbyname('echo', 'udp');
    my $sockaddr = _pack_sockaddr_in($port, $ip);
    my ($error, $address) = getnameinfo($sockaddr, $NI_NUMERICHOST);
    croak $error if $error;
    return $address;
}

sub wakeonlan {
  my ($mac_addr, $host, $port) = @_;

  # use the discard service if $port not passed in
  if (! defined $host) { $host = '255.255.255.255' }
  if (! defined $port || $port !~ /^\d+$/ ) { $port = 9 }

  require IO::Socket::INET;
  my $sock = IO::Socket::INET->new(Proto=>'udp') || return undef;

  my $ip_addr = inet_aton($host);
  my $sock_addr = sockaddr_in($port, $ip_addr);
  $mac_addr =~ s/://g;
  my $packet = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

  setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1);
  send($sock, $packet, 0, $sock_addr);
  $sock->close;

  return 1;
}

sub _resolv {
  my ($self,
      $name,
      ) = @_;

  my %h;
  $h{name} = $name;
  my $family = $self->{family};

  if (defined($self->{family_local})) {
    $family = $self->{family_local}
  }

  my $cnt = 0;

  # Count ":"
  $cnt++ while ($name =~ m/:/g);

  # 0 = hostname or IPv4 address
  if ($cnt == 0) {
    $h{host} = $name
  # 1 = IPv4 address with port
  } elsif ($cnt == 1) {
    ($h{host}, $h{port}) = split /:/, $name
  # >=2 = IPv6 address
  } elsif ($cnt >= 2) {
    #IPv6 with port - [2001::1]:port
    if ($name =~ /^\[.*\]:\d{1,5}$/) {
      ($h{host}, $h{port}) = split /:([^:]+)$/, $name # split after last :
    # IPv6 without port
    } else {
      $h{host} = $name
    }
  }

  # Clean up host
  $h{host} =~ s/\[//g;
  $h{host} =~ s/\]//g;
  # Clean up port
  if (defined($h{port}) && (($h{port} !~ /^\d{1,5}$/) || ($h{port} < 1) || ($h{port} > 65535))) {
    croak("Invalid port `$h{port}' in `$name'");
    return undef;
  }

  # address check
  # new way
  if ($Socket_VERSION > 1.94) {
    my %hints = (
      family   => $AF_UNSPEC,
      protocol => IPPROTO_TCP,
      flags => $AI_NUMERICHOST
    );

    # numeric address, return
    my ($err, @getaddr) = Socket::getaddrinfo($h{host}, undef, \%hints);
    if (defined($getaddr[0])) {
      $h{addr} = $h{host};
      $h{family} = $getaddr[0]->{family};
      if ($h{family} == AF_INET) {
        (undef, $h{addr_in}, undef, undef) = Socket::unpack_sockaddr_in $getaddr[0]->{addr};
      } else {
        (undef, $h{addr_in}, undef, undef) = Socket::unpack_sockaddr_in6 $getaddr[0]->{addr};
      }
      return \%h
    }
  # old way
  } else {
    # numeric address, return
    my $ret = gethostbyname($h{host});
    if (defined($ret) && (_inet_ntoa($ret) eq $h{host})) {
      $h{addr} = $h{host};
      $h{addr_in} = $ret;
      $h{family} = AF_INET;
      return \%h
    }
  }

  # resolve
  # new way
  if ($Socket_VERSION >= 1.94) {
    my %hints = (
      family   => $family,
      protocol => IPPROTO_TCP
    );

    my ($err, @getaddr) = Socket::getaddrinfo($h{host}, undef, \%hints);
    if (defined($getaddr[0])) {
      my ($err, $address) = Socket::getnameinfo($getaddr[0]->{addr}, $NI_NUMERICHOST, $NIx_NOSERV);
      if (defined($address)) {
        $h{addr} = $address;
        $h{addr} =~ s/\%(.)*$//; # remove %ifID if IPv6
        $h{family} = $getaddr[0]->{family};
        if ($h{family} == AF_INET) {
          (undef, $h{addr_in}, undef, undef) = Socket::unpack_sockaddr_in $getaddr[0]->{addr};
        } else {
          (undef, $h{addr_in}, undef, undef) = Socket::unpack_sockaddr_in6 $getaddr[0]->{addr};
        }
        return \%h;
      } else {
        carp("getnameinfo($getaddr[0]->{addr}) failed - $err");
        return undef;
      }
    } else {
      warn(sprintf("getaddrinfo($h{host},,%s) failed - $err",
                    $family == AF_INET ? "AF_INET" : "AF_INET6"));
      return undef;
    }
  # old way
  } else {
    if ($family == $AF_INET6) {
      croak("Socket >= 1.94 required for IPv6 - found Socket $Socket::VERSION");
      return undef;
    }

    my @gethost = gethostbyname($h{host});
    if (defined($gethost[4])) {
      $h{addr} = inet_ntoa($gethost[4]);
      $h{addr_in} = $gethost[4];
      $h{family} = AF_INET;
      return \%h
    } else {
      carp("gethostbyname($h{host}) failed - $^E");
      return undef;
    }
  }
  return undef;
}

sub _pack_sockaddr_in($$) {
  my ($port,
      $ip,
      ) = @_;

  my $addr = ref($ip) eq "HASH" ? $ip->{addr_in} : $ip;
  if (length($addr) <= 4 ) {
    return Socket::pack_sockaddr_in($port, $addr);
  } else {
    return Socket::pack_sockaddr_in6($port, $addr);
  }
}

sub _unpack_sockaddr_in($;$) {
  my ($addr,
      $family,
      ) = @_;

  my ($port, $host);
  if ($family == AF_INET || (!defined($family) and length($addr) <= 16 )) {
    ($port, $host) = Socket::unpack_sockaddr_in($addr);
  } else {
    ($port, $host) = Socket::unpack_sockaddr_in6($addr);
  }
  return $port, $host
}

sub _inet_ntoa {
  my ($addr
      ) = @_;

  my $ret;
  if ($Socket_VERSION >= 1.94) {
    my ($err, $address) = Socket::getnameinfo($addr, $NI_NUMERICHOST);
    if (defined($address)) {
      $ret = $address;
    } else {
      carp("getnameinfo($addr) failed - $err");
    }
  } else {
    $ret = inet_ntoa($addr)
  }
    
  return $ret
}

1;
__END__

