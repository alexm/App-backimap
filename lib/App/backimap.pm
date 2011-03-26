package App::backimap;
# ABSTRACT: backups imap mail

=head1 SYNOPSIS

    use App::backimap;
    App::backimap->new(@ARGV)->run();

=cut

use strict;
use warnings;

use Moose;
use App::backimap::Status;
use App::backimap::Status::Folder;
use App::backimap::IMAP;
use App::backimap::Storage;

=attr status

Application persistent status.

=cut

has status => (
    is => 'rw',
    isa => 'App::backimap::Status',
);

=attr imap

An object to encapsulate IMAP details.

=cut

has imap => (
    is => 'rw',
    isa => 'App::backimap::IMAP',
);

=attr storage

Storage backend where files and messages are stored.

=cut

has storage => (
    is => 'rw',
    isa => 'App::backimap::Storage',
);

use Getopt::Long         qw( GetOptionsFromArray );
use Pod::Usage;
use URI;
use Path::Class qw( file );

=method new

Creates a new program instance with command line arguments.

=cut

sub new {
    my ( $class, @argv ) = @_;

    my %opt = (
        help    => 0,
        verbose => 0,
        dir     => undef,
        init    => 0,
        clean   => 0,
    );

    GetOptionsFromArray(
        \@argv,
        \%opt,

        'help|h',
        'verbose|v',
        'dir=s',
        'init!',
        'clean!',
    )
        or __PACKAGE__->usage();

    $opt{'args'} = \@argv;

    return bless \%opt, $class;
}

=method setup

Setups storage, IMAP connection and backimap status.

=cut

sub setup {
    my ( $self, $str ) = @_;

    my $storage = App::backimap::Storage->new(
        dir   => $self->{'dir'},
        init  => $self->{'init'},
        clean => $self->{'clean'},
    );
    $self->storage($storage);

    my $uri  = URI->new($str);
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

    my $imap = $self->imap->client;
    my @folder_list = $self->imap->path ne ''
                    ? $self->imap->path
                    : $imap->folders;

    print STDERR "Examining folders...\n"
        if $self->{'verbose'};

    for my $folder (@folder_list) {
        my $count  = $imap->message_count($folder);
        next unless defined $count;

        my $unseen = $imap->unseen_count($folder);

        if ( $self->status->folder && exists $self->status->folder->{$folder} ) {
            $self->status->folder->{$folder}->count($count);
            $self->status->folder->{$folder}->unseen($unseen);
        }
        else {
            my $status = App::backimap::Status::Folder->new(
                count => $count,
                unseen => $unseen,
            );

            $self->status->folder({ $folder => $status });
        }

        print STDERR " * $folder ($unseen/$count)"
            if $self->{'verbose'};

        # list of potential files to purge
        my %purge = map { $_ => 1 } $self->storage->list($folder);

        $imap->examine($folder);
        for my $msg ( $imap->messages ) {
            # do not purge if still present in server
            delete $purge{$msg};

            my $file = file( $folder, $msg );
            next if $self->storage->find($file);

            my $fetch = $imap->fetch( $msg, 'RFC822' );
            $self->storage->put( "$file" => $fetch->[2] );
        }

        my @purge = map { file( $folder, $_ ) } keys %purge;
        if (@purge) {
            print STDERR " (@purge)"
                if $self->{'verbose'};

            $self->storage->delete(@purge);
        }

        print STDERR "\n"
            if $self->{'verbose'};
    }
}

=method run

Parses command line arguments and starts the program.

=cut

sub run {
    my ($self) = @_;

    my @args = @{ $self->{'args'} };
    $self->usage unless @args == 1;

    $self->setup(@args);

    my $start = time();
    $self->backup();
    my $spent = ( time() - $start ) / 60;
    my $message = sprintf "backup took %.2f minutes", $spent;

    $self->status->save();
    $self->storage->commit($message);

    printf STDERR "$message\n"
        if $self->{'verbose'};
}

=method usage

Shows an usage summary.

=cut

sub usage {
    my ($self) = @_;

    pod2usage( verbose => 0, exitval => 1 );
}

1;
