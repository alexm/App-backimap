use strict;
use warnings;

package App::backimap;
# ABSTRACT: backups imap mail

=head1 SYNOPSIS

    use App::backimap;
    App::backimap->new_with_options()->run();

=cut

use Moose;
with 'MooseX::Getopt';

use Moose::Util::TypeConstraints;
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
use Data::Dump();
use Term::ProgressBar();

=head1 OPTIONS

=over 4

=item --uri STRING

For instance: imaps://user@example.org@imap.example.org/folder

=item --exclude STRING

Folder name to exclude from backup (e.g. spam)

=item --dir PATH

Defaults to: ~/.backimap

=item --init

=item --clean

=item --resume

=item --incremental

=item --explode

=item --verbose

=back

=cut

has uri => (
    is => 'ro',
    isa => 'Str',
    documentation => 'URI for the remote IMAP folder.',
    required => 1,
);

subtype 'ArrayOfUtf8'
    => as 'ArrayRef';

coerce 'ArrayOfUtf8'
    => from 'ArrayRef'
    => via { Encode::encode( 'utf-8', $_ ) };

MooseX::Getopt::OptionTypeMap->add_option_type_to_map(
    'ArrayOfUtf8' => '=s@'
);

has exclude => (
    is => 'ro',
    isa => 'ArrayOfUtf8',
    documentation => 'Folder name to exclude from backup (e.g. spam).',
    default => sub { [] },
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

has resume => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
    documentation => 'Resume previous failed backup.',
);

has incremental => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
    documentation => 'Perform an incremental backup since last time.',
);

has explode => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
    documentation => 'Explode message MIME parts (e.g. attachments).',
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

=method is_excluded( $folder )

Returns boolean indicating that $folder is on the excluded list of folders.

=cut

sub is_excluded {
    my $self = shift;
    my ($folder) = @_;

    return ! !grep $_ eq $folder, @{ $self->exclude };
}

=method setup()

Setups storage, IMAP connection and backimap status.

=cut

sub setup {
    my $self = shift;

    my $storage = App::backimap::Storage->new(
        dir    => $self->dir,
        init   => $self->init,
        clean  => $self->clean,
        resume => $self->resume,
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

=method backup()

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
            next if $self->is_excluded($folder_name);

            my $count  = $imap->message_count($folder);
            next unless defined $count;

            my $unseen = $imap->unseen_count($folder);

            my $folder_id = $imap->uidvalidity($folder);
    
            my $new_status = App::backimap::Status::Folder->new(
                count => $count,
                unseen => $unseen,
                name => $folder_name,
            );

            if ( !$status_of ) {
                $self->status->folder({ $folder_id => $new_status });
                $status_of = $self->status->folder;
            }
            elsif ( !exists $status_of->{$folder_id} ) {
                $status_of->{$folder_id} = $new_status;
            }
            else {
                $status_of->{$folder_id}->count($count);
                $status_of->{$folder_id}->unseen($unseen);

                if ( $folder_name ne $status_of->{$folder_id}->name ) {
                    $storage->move( $status_of->{$folder_id}->name, $folder_name );
                    $status_of->{$folder_id}->name($folder_name);
                }
            }

            $imap->examine($folder);
            my @messages = $self->incremental
                         ? $imap->since( $self->status->timestamp )
                         : $imap->messages
                         ;

            my $msg_count = @messages;

            my $progress_update = 0;
            my $progress;

            if ( $self->verbose ) {
                my $text = " * $folder_name ($msg_count/$unseen/$count)";

                if ( $msg_count > 0 ) {
                    $progress = Term::ProgressBar->new({
                        name => $text,
                        count => $msg_count,
                        ETA => 'linear',
                        fh => \*STDERR,
                        remove => 0,
                    });
                }
                else {
                    print STDERR $text;
                }
            }

            $progress->update($progress_update++)
                if $self->verbose && $msg_count > 0;
    
            # list of potential files to purge
            my %purge;
            %purge = map { $_ => 1 } $storage->list($folder_name)
                unless $self->incremental;
    
            for my $msg (@messages) {
                $progress->update($progress_update++)
                    if $self->verbose;

                # do not purge if still present in server
                delete $purge{$msg}
                    unless $self->incremental;
    
                my $file = file( $folder_name, $msg );
                next if $storage->find($file);
    
                my $fetch = $imap->fetch( $msg, 'RFC822' );
                my $op = $self->explode ? 'explode' : 'put';
                $storage->$op( "$file" => $fetch->[2] );
            }

            $progress->update($msg_count)
                if $self->verbose && $msg_count > 0;
    
            if ( !$self->incremental && %purge ) {
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
        if ( $imap->LastError ) {
            print STDERR "OOPS! Error in IMAP transaction... ",
                         $imap->LastError,
                         "\n\n",
                         Data::Dump::pp( $imap->Results );
        }
        elsif ( $_ ne '' ) {
            print STDERR "OOPS! $_";
        }

        die sprintf( "\ntime=%.2f\n", ( $^T - time ) / 60 );
    }
}

=method run()

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
