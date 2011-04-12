#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

use Test::TestCoverage;

my $class = 'App::backimap::Status::Folder';
my %attributes = (
    count => 0,
    unseen => 0,
    name => 'foobar',
);

plan tests => 4 + (keys %attributes);

use_ok($class);

for my $attr (keys %attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

test_coverage($class);

my $folder = $class->new(%attributes);

isa_ok( $folder, $class );

my %meta_attrs = map {
    my $name = $_->name;
    $name => $folder->$name
} $folder->meta->get_all_attributes();

is_deeply( \%meta_attrs, \%attributes, 'attributes and accessors coverage' );

ok_test_coverage($class);
