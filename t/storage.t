#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

use Test::TestCoverage;
use Path::Class::Dir();

my $tmp_dir = Path::Class::Dir->new('t/tmp');
my $class = 'App::backimap::Storage';
my %args = (
    dir => $tmp_dir,
    init => 1,
    clean => 0,
    author => 'me',
    email => 'me@me.me',
    # NOTE: _git => Git::Wrapper->new($tmp_dir)
);

my @attributes = ( keys %args, '_git' );

my @methods = qw( find list get put delete move commit reset pack unpack );

plan tests => 15 + @attributes;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

can_ok( $class, @methods );

test_coverage($class);

my $storage = $class->new(%args);

isa_ok( $storage, $class );

my %meta_attrs = map {
    my $name = $_->name;
    $name => $storage->$name
} $storage->meta->get_all_attributes();

is_deeply(
    \%meta_attrs,
    {
        %args,

        # NOTE: _git is a derived attribute
        _git => Git::Wrapper->new('t/tmp'),
    },
    'attributes and accessors coverage',
);

is( $storage->pack(), undef, 'pack does nothing' );
is( $storage->unpack(), undef, 'unpack does nothing' );

$storage->put( file1 => 'content1' );
is( $storage->get('file1'), 'content1', 'get file after put' );
is_deeply( [ $storage->list('/') ], [ 'file1' ], 'list files' );

$storage->move( 'file1', 'file2' );
is( $storage->get('file2'), 'content1', 'get file after move' );
is_deeply( [ $storage->list('/') ], [ 'file2' ], 'list files after move' );

is_deeply( [ $storage->find(qw( file1 file2 )) ], [ 'file2' ], 'find existing files' );
is_deeply( [ $storage->find(qw( file1 file3 )) ], [         ], 'find non-existing files' );

$storage->commit('test file2');
$storage->delete('file2');
is_deeply( [ $storage->list('/') ], [], 'list files after delete' );

$storage->reset();
is_deeply( [ $storage->list('/') ], [ 'file2' ], 'list after reset' );

ok_test_coverage($class);
$tmp_dir->rmtree();
