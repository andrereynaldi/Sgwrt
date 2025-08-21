
package IPC::SharedMem;

use IPC::SysV qw(IPC_STAT IPC_RMID shmat shmdt memread memwrite);
use strict;
use vars qw($VERSION);
use Carp;

$VERSION = '2.09';

my $N = do { my $foo = eval { pack "L!", 0 }; $@ ? '' : '!' };

{
    package IPC::SharedMem::stat;

    use Class::Struct qw(struct);

    struct 'IPC::SharedMem::stat' => [
	uid	=> '$',
	gid	=> '$',
	cuid	=> '$',
	cgid	=> '$',
	mode	=> '$',
	segsz	=> '$',
	lpid	=> '$',
	cpid	=> '$',
	nattch	=> '$',
	atime	=> '$',
	dtime	=> '$',
	ctime	=> '$',
    ];
}

sub new
{
  @_ == 4 or croak 'IPC::SharedMem->new(KEY, SIZE, FLAGS)';
  my($class, $key, $size, $flags) = @_;

  my $id = shmget $key, $size, $flags;

  return undef unless defined $id;

  bless { _id => $id, _addr => undef, _isrm => 0 }, $class
}

sub id
{
  my $self = shift;
  $self->{_id};
}

sub addr
{
  my $self = shift;
  $self->{_addr};
}

sub stat
{
  my $self = shift;
  my $data = '';
  shmctl $self->id, IPC_STAT, $data or return undef;
  IPC::SharedMem::stat->new->unpack($data);
}

sub attach
{
  @_ >= 1 && @_ <= 2 or croak '$shm->attach([FLAG])';
  my($self, $flag) = @_;
  defined $self->addr and return undef;
  $self->{_addr} = shmat($self->id, undef, $flag || 0);
  defined $self->addr;
}

sub detach
{
  my $self = shift;
  defined $self->addr or return undef;
  my $rv = defined shmdt($self->addr);
  undef $self->{_addr} if $rv;
  $rv;
}

sub remove
{
  my $self = shift;
  return undef if $self->is_removed;
  my $rv = shmctl $self->id, IPC_RMID, 0;
  $self->{_isrm} = 1 if $rv;
  return $rv;
}

sub is_removed
{
  my $self = shift;
  $self->{_isrm};
}

sub read
{
  @_ == 3 or croak '$shm->read(POS, SIZE)';
  my($self, $pos, $size) = @_;
  my $buf = '';
  if (defined $self->addr) {
    memread($self->addr, $buf, $pos, $size) or return undef;
  }
  else {
    shmread($self->id, $buf, $pos, $size) or return undef;
  }
  $buf;
}

sub write
{
  @_ == 4 or croak '$shm->write(STRING, POS, SIZE)';
  my($self, $str, $pos, $size) = @_;
  if (defined $self->addr) {
    return memwrite($self->addr, $str, $pos, $size);
  }
  else {
    return shmwrite($self->id, $str, $pos, $size);
  }
}

1;

__END__


