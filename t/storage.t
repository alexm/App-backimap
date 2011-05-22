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
    resume => 0,
    author => 'me',
    email => 'me@me.me',
    # NOTE: _git => Git::Wrapper->new($tmp_dir)
);

my @attributes = ( keys %args, '_git' );

my @methods = qw( find list get put delete move commit reset pack unpack );

plan tests => 26 + @attributes;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

can_ok( $class, 'new', @methods, @attributes );

test_coverage($class);
test_coverage_except( $class, qw( BUILD ) );

{
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

    $tmp_dir->rmtree();
}

{
    # simulate a failed backup without committing file3
    my $storage = $class->new(%args);
    isa_ok( $storage, $class );
    $storage->put( file => 'file content' );
    $storage->commit('test file');
    $storage->put( failed => 'failed content' );

    # resume previous scheduled operation
    my $other_storage = $class->new( %args, init => 0, resume => 1 );
    isa_ok( $other_storage, $class );
    is_deeply( [ $other_storage->find('failed') ], [ 'failed' ], 'list after resume' );
    is( $other_storage->get('failed'), 'failed content', 'get after resume' );

    $tmp_dir->rmtree();
}

{
    # simulate a failed backup with an unknown file4
    my $storage = $class->new(%args);
    isa_ok( $storage, $class );
    $storage->put( file => 'file content' );
    $storage->commit('test file');
    my $file4 = $tmp_dir->file('unknown');
    my $fh = $file4->openw();
    $fh->print('unknown content');
    $fh->close;
    ok( -f $file4, 'unknown created but not scheduled' );

    # test previous failed simulation
    my $other_storage = $class->new( %args, init => 0, resume => 1 );
    isa_ok( $other_storage, $class );
    is_deeply( [ $other_storage->find('unknown') ], [], 'list after resume without unknown' );

    $tmp_dir->rmtree();
}

{
    # explode a trivial MIME content
    my $storage = $class->new(%args);
    isa_ok( $storage, $class );
    my $text = "Hello, world!";
    $storage->explode( mime => <<"EOF" );
Content-Type: text/plain; charset=US-ASCII; name="hello.txt"

$text
EOF
    is_deeply(
        [ sort $storage->list("/mime") ],
        [ sort '__MIME__', 'hello.txt' ],
        'list after explode MIME',
    );
    is( $storage->get('/mime/hello.txt'), "$text\n", 'get exploded MIME content' );

    $tmp_dir->rmtree();
}

ok_test_coverage($class);
