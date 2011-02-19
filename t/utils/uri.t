#!perl

use strict;
use warnings;

use Test::More;

use URI;
use App::backimap::Utils qw( imap_uri_split );

my %test_case = (
    'imap:' => {
        secure => 0,
        user => undef,
        password => undef,
        host => undef,
        port => 143,
        path => '',
    },

    'imaps:' => {
        secure => 1,
        user => undef,
        password => undef,
        host => undef,
        port => 993,
        path => '',
    },

    'imap://server.example.com' => {
        secure => 0,
        user => undef,
        password => undef,
        host   => 'server.example.com',
        port => 143,
        path => '',
    },

    'imaps://server.example.com' => {
        secure => 1,
        user => undef,
        password => undef,
        host   => 'server.example.com',
        port => 993,
        path => '',
    },

    'imap://user@example.com@server.example.com' => {
        secure => 0,
        user   => 'user@example.com',
        password => undef,
        host   => 'server.example.com',
        port => 143,
        path => '',
    },

    'imaps://user@example.com@server.example.com' => {
        secure => 1,
        user   => 'user@example.com',
        password => undef,
        host   => 'server.example.com',
        port => 993,
        path => '',
    },

    'imap://user@example.com:password@server.example.com' => {
        secure => 0,
        user   => 'user@example.com',
        password => 'password',
        host   => 'server.example.com',
        port => 143,
        path => '',
    },

    'imaps://user@example.com:password@server.example.com' => {
        secure => 1,
        user   => 'user@example.com',
        password => 'password',
        host   => 'server.example.com',
        port => 993,
        path => '',
    },

    'imap://user@example.com:password@server.example.com/foo/bar' => {
        secure => 0,
        user   => 'user@example.com',
        password => 'password',
        host   => 'server.example.com',
        port => 143,
        path => '/foo/bar',
    },

    'imaps://user@example.com:password@server.example.com/foo/bar' => {
        secure => 1,
        user   => 'user@example.com',
        password => 'password',
        host   => 'server.example.com',
        port => 993,
        path => '/foo/bar',
    },
);

plan tests => scalar keys %test_case;
for my $test (sort keys %test_case) {
    is_deeply( imap_uri_split( URI->new($test) ), $test_case{$test}, $test );
}
