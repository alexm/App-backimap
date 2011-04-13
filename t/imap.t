#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

use Test::TestCoverage;
use Test::MockModule;

use URI();

my $class = 'App::backimap::IMAP';
my %attributes = (
    uri => URI->new('imaps://user:pass@example.com/INBOX'),
    # user => 'user',
    # host => 'example.com',
    # port => 993,
    # secure => 1,
    # password => 'pass',
    # path => 'INBOX',

    # NOTE: client => {} (see mocking below)
);

plan tests => 4 + (keys %attributes);

use_ok($class);

for my $attr (keys %attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

my $Mail_IMAPClient = 'Mail::IMAPClient';
my $client = Test::MockModule->new($Mail_IMAPClient);
$client->mock( IsAuthenticated => sub { 1 } );
$client->mock( new => sub { bless {}, $Mail_IMAPClient } );

test_coverage($class);

my $imap = $class->new(%attributes);

isa_ok( $imap, $class );

my %meta_attrs = map {
    my $name = $_->name;
    $name => $imap->$name
} $imap->meta->get_all_attributes();

is_deeply(
    \%meta_attrs,
    {
        %attributes,
        user => 'user',
        host => 'example.com',
        port => 993,
        secure => 1,
        password => 'pass',
        path => 'INBOX',

        # NOTE: client is mocked
        client => {},
    },
    'attributes and accessors coverage',
);

ok_test_coverage($class);
