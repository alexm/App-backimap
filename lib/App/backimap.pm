package App::backimap;
# ABSTRACT: backups imap mail

=head1 SYNOPSIS

    use App::backimap;
    App::backimap->new_with_options()->run();

=cut

use strict;
use warnings;

use Moose;
with 'MooseX::Getopt';

use MooseX::Types::Path::Class;
use App::backimap::Status;
use App::backimap::Status::Folder;
use App::backimap::IMAP;
use App::backimap::Storage;
use Try::Tiny;
use Encode::IMAPUTF7();
use Encode();
use Path::Class qw( file );
use URI();

=head1 OPTIONS

=over 4

=item --uri STRING

For instance: imaps://user@example.org@imap.example.org/folder

=item --dir PATH

Defaults to: ~/.backimap

=item --init

=item --clean

=item --verbose

=back

=cut

has uri => (
    is => 'ro',
    isa => 'Str',
    documentation => 'URI for the remote IMAP folder.',
    required => 1,
);

has dir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    coerce => 1,
    documentation => 'Path to storage (default: ~/.backimap)',
);

has init => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
    documentation => 'Initialize storage and setup backimap status.',
);

has clean => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
    documentation => 'Clean up storage if dirty.',
);

has verbose => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
    documentation => 'Enable verbose messages.',
);

=attr status

Application persistent status.

=cut

has _status => (
    accessor => 'status',
    is => 'rw',
    isa => 'App::backimap::Status',
);

=attr imap

An object to encapsulate IMAP details.

=cut

has _imap => (
    accessor => 'imap',
    is => 'rw',
    isa => 'App::backimap::IMAP',
);

=attr storage

Storage backend where files and messages are stored.

=cut

has _storage => (
    accessor => 'storage',
    is => 'rw',
    isa => 'App::backimap::Storage',
);

=method setup

Setups storage, IMAP connection and backimap status.

=cut

sub setup {
    my $self = shift;

    my $storage = App::backimap::Storage->new(
        dir   => $self->dir,
        init  => $self->init,
        clean => $self->clean,
    );
    $self->storage($storage);

    my $uri  = URI->new( $self->uri );
    my $imap = App::backimap::IMAP->new( uri => $uri );
    $self->imap($imap);

    my $status = App::backimap::Status->new(
        storage => $storage,
        server  => $imap->host,
        user    => $imap->user,
    );
    $self->status($status);
}

=method backup

Perform IMAP folder backup recursively.

=cut

sub backup {
    my ($self) = @_;

    my $storage = $self->storage;
    my $status_of = $self->status->folder;

    my $imap = $self->imap->client;
    my @folder_list = $self->imap->path ne ''
                    ? $self->imap->path
                    : $imap->folders;

    print STDERR "Examining folders...\n"
        if $self->verbose;

    try {
        for my $folder (@folder_list) {
            my $folder_name = Encode::encode( 'utf-8', Encode::decode( 'imap-utf-7', $folder ) );
            my $count  = $imap->message_count($folder);
            next unless defined $count;
    
            my $unseen = $imap->unseen_count($folder);
    
            if ( $status_of && exists $status_of->{$folder_name} ) {
                $status_of->{$folder_name}->count($count);
                $status_of->{$folder_name}->unseen($unseen);
            }
            else {
                my $new_status = App::backimap::Status::Folder->new(
                    count => $count,
                    unseen => $unseen,
                );
    
                $self->status->folder({ $folder_name => $new_status });
            }
    
            print STDERR " * $folder_name ($unseen/$count)"
                if $self->verbose;
    
            # list of potential files to purge
            my %purge = map { $_ => 1 } $storage->list($folder_name);
    
            $imap->examine($folder);
            for my $msg ( $imap->messages ) {
                # do not purge if still present in server
                delete $purge{$msg};
    
                my $file = file( $folder_name, $msg );
                next if $storage->find($file);
    
                my $fetch = $imap->fetch( $msg, 'RFC822' );
                $storage->put( "$file" => $fetch->[2] );
            }
    
            if (%purge) {
                local $, = q{ };
                print STDERR " (", keys %purge, ")"
                    if $self->verbose;

                my @purge = map { file( $folder_name, $_ ) } keys %purge;
                $storage->delete(@purge);
            }
    
            print STDERR "\n"
                if $self->verbose;
        }
    }
    catch {
        die "oops! error in IMAP transaction...\n\n" .
            $imap->Results .
            sprintf( "\ntime=%.2f\n", ( $^T - time ) / 60 );
    }
}

=method run

Parses command line arguments and starts the program.

=cut

sub run {
    my $self = shift;

    $self->setup();

    my $start = time();
    $self->backup();
    my $spent = ( time() - $start ) / 60;
    my $message = sprintf "backup took %.2f minutes", $spent;

    $self->status->save();
    $self->storage->commit($message);

    printf STDERR "$message\n"
        if $self->verbose;
}

1;
