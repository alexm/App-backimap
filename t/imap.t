#!perl

use strict;
use warnings;

use Test::More;
use Test::Moose;

use Test::MockModule;

use URI();

my $class = 'App::backimap::IMAP';
my %args = (
    uri => URI->new('imaps://user:pass@example.com/INBOX'),
    # user => 'user',
    # host => 'example.com',
    # port => 993,
    # secure => 1,
    # password => 'pass',
    # path => 'INBOX',

    # NOTE: client => {} (see mocking below)
);

my @attributes = ( keys %args, qw(
    user
    host
    port
    secure
    password
    path
    client
));

plan tests => 4 + @attributes;

use_ok($class);

for my $attr (@attributes) {
    has_attribute_ok( $class, $attr, "$class has the '$attr' attribute" );
}

can_ok( $class, 'new', @attributes );

my $Mail_IMAPClient = 'Mail::IMAPClient';
my $client = Test::MockModule->new($Mail_IMAPClient);
$client->mock( IsAuthenticated => sub { 1 } );
$client->mock( new => sub { bless {}, $Mail_IMAPClient } );

my $imap = $class->new(%args);

isa_ok( $imap, $class );

my %meta_attrs = map {
    my $name = $_->name;
    $name => $imap->$name
} $imap->meta->get_all_attributes();

is_deeply(
    \%meta_attrs,
    {
        %args,
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
