use Test::More tests => 10;

use strict;
use warnings;
use File::Spec;
use lib 't/lib';
$|++;

use TestSupport qw(create_test_files delete_test_files move_test_files
  modify_attrs_on_test_files $dir received_events receive_event);

use AnyEvent::Filesys::Notify;
use AnyEvent::Impl::Perl;

create_test_files(qw(one/1));
create_test_files(qw(two/1));
create_test_files(qw(one/sub/1));
## ls: one/1 one/sub/1 two/1

my $n = AnyEvent::Filesys::Notify->new(
    dirs         => [ map { File::Spec->catfile( $dir, $_ ) } qw(one two) ],
    filter       => sub   { shift !~ qr/ignoreme/ },
    cb           => sub   { receive_event(@_) },
    parse_events => 1,
);
isa_ok( $n, 'AnyEvent::Filesys::Notify' );

diag "This might take a few seconds to run...";

# ls: one/1 one/sub/1 +one/sub/2 two/1
received_events( sub { create_test_files(qw(one/sub/2)) },
    'create a file', qw(created) );

# ls: one/1 +one/2 one/sub/1 one/sub/2 two/1 +two/sub/2
received_events(
    sub { create_test_files(qw(one/2 two/sub/2)) },
    'create file in new subdir',
    qw(created created created)
);

# ls: ~one/1 one/2 one/sub/1 one/sub/2 two/1 two/sub/2
# Inotify2 generates two modified events when a file is modified
{
    my @expected =
      $n->does('AnyEvent::Filesys::Notify::Role::Inotify2')
      ? qw(modified modified)
      : qw(modified);
    received_events( sub { create_test_files(qw(one/1)) },
        'modify existing file', @expected );
}

# ls: one/1 one/2 one/sub/1 one/sub/2 two/1 two/sub -two/sub/2
received_events( sub { delete_test_files(qw(two/sub/2)) },
    'deletes a file', qw(deleted) );

# ls: one/1 one/2 +one/ignoreme +one/3 one/sub/1 one/sub/2 two/1 two/sub
received_events( sub { create_test_files(qw(one/ignoreme one/3)) },
    'creates two files one should be ignored', qw(created) );

# ls: one/1 one/2 one/ignoreme -one/3 +one/5 one/sub/1 one/sub/2 two/1 two/sub
received_events( sub { move_test_files( 'one/3' => 'one/5' ) },
    'move files', qw(deleted created) );

SKIP: {
    skip "skip attr mods on Win32", 1 if $^O eq 'MSWin32';

    # ls: one/1 one/2 one/ignoreme one/5 one/sub/1 one/sub/2 ~two/1 ~two/sub
    # Inotify2 generates an extra modified event when attributes changed
    my @expected =
      $n->does('AnyEvent::Filesys::Notify::Role::Inotify2')
      ? qw(modified modified modified)
      : qw(modified modified);
    received_events( sub { modify_attrs_on_test_files(qw(two/1 two/sub)) },
        'modify attributes', @expected );

}

# ls: one/1 one/2 one/ignoreme +one/onlyme +one/4 one/5 one/sub/1 one/sub/2 two/1 two/sub
$n->filter(qr/onlyme/);
received_events( sub { create_test_files(qw(one/onlyme one/4)) },
    'filter test', qw(created) );

ok( 1, '... arrived' );

