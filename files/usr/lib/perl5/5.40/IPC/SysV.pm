
package IPC::SysV;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $AUTOLOAD);
use Carp;
use Config;

require Exporter;
@ISA = qw(Exporter);

$VERSION = '2.09';

@EXPORT_OK = (qw(

  GETALL GETNCNT GETPID GETVAL GETZCNT

  IPC_ALLOC IPC_CREAT IPC_EXCL IPC_GETACL IPC_INFO IPC_LOCKED
  IPC_M IPC_NOERROR IPC_NOWAIT IPC_PRIVATE IPC_R IPC_RMID
  IPC_SET IPC_SETACL IPC_SETLABEL IPC_STAT IPC_W IPC_WANTED

  MSG_EXCEPT MSG_FWAIT MSG_INFO MSG_LOCKED MSG_MWAIT MSG_NOERROR
  MSG_QWAIT MSG_R MSG_RWAIT MSG_STAT MSG_W MSG_WAIT MSG_WWAIT

  SEM_A SEM_ALLOC SEM_DEST SEM_ERR SEM_INFO SEM_ORDER SEM_R
  SEM_STAT SEM_UNDO

  SETALL SETVAL

  SHMLBA

  SHM_A SHM_CLEAR SHM_COPY SHM_DCACHE SHM_DEST SHM_ECACHE
  SHM_FMAP SHM_HUGETLB SHM_ICACHE SHM_INFO SHM_INIT SHM_LOCK
  SHM_LOCKED SHM_MAP SHM_NORESERVE SHM_NOSWAP SHM_R SHM_RDONLY
  SHM_REMAP SHM_REMOVED SHM_RND SHM_SHARE_MMU SHM_SHATTR
  SHM_SIZE SHM_STAT SHM_UNLOCK SHM_W

  S_IRUSR S_IWUSR S_IXUSR S_IRWXU
  S_IRGRP S_IWGRP S_IXGRP S_IRWXG
  S_IROTH S_IWOTH S_IXOTH S_IRWXO

  ENOSPC ENOSYS ENOMEM EACCES

), qw(

  ftok shmat shmdt memread memwrite

));

%EXPORT_TAGS = (
  all => [@EXPORT, @EXPORT_OK],
);

sub AUTOLOAD
{
  my $constname = $AUTOLOAD;
  $constname =~ s/.*:://;
  die "&IPC::SysV::_constant not defined" if $constname eq '_constant';
  my ($error, $val) = _constant($constname);
  if ($error) {
    my (undef, $file, $line) = caller;
    die "$error at $file line $line.\n";
  }
  {
    no strict 'refs';
    *$AUTOLOAD = sub { $val };
  }
  goto &$AUTOLOAD;
}

BOOT_XS: {
  # If I inherit DynaLoader then I inherit AutoLoader and I DON'T WANT TO
  use XSLoader ();

  XSLoader::load( 'IPC::SysV', $VERSION );

}

1;

__END__


