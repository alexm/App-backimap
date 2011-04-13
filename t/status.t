#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

use Test::TestCoverage;

my $class = 'App::backimap::Status';
my %args = (
    timestamp => 0,
    server => 'server',
    user => 'user',
    folder => {},
    # NOTE: storage => undef (via meta), see below
);

my @attributes = ( keys %args, 'storage' );

my @methods = qw( save );

plan tests => 6 + @attributes;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

can_ok( $class, 'new', @methods, @attributes );

test_coverage($class);
test_coverage_except( $class, qw( BUILD ) );

# new covers BUILD too
my $status = $class->new(%args);

isa_ok( $status, $class );

my %meta_attrs = map {
    my $name = $_->name;
    $name => $status->$name
} $status->meta->get_all_attributes();

is_deeply(
    \%meta_attrs,
    {
        %args,

        # NOTE: storage => undef (via meta), see above
        storage => undef,
    },
    'attributes and accessors coverage',
);

is( $status->save(), undef, 'save() does nothing w/o storage' );

ok_test_coverage($class);
