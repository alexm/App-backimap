use strict;
use warnings;

package App::backimap::Storage;
# ABSTRACT: manages backimap storage

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class;
use File::HomeDir;
use Git::Wrapper;
use IO::Scalar;
use MIME::Parser;
use Encode;
use Storable;

=attr dir

Sets pathname to the storage (defaults to ~/.backimap).

=cut

has dir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    required => 1,
    coerce => 1,
    builder => '_build_dir',
);

sub _build_dir { return File::HomeDir->my_home . ".backimap" }

=attr init

Tells that storage must be initialized.

=cut

has init => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
);

=attr clean

Tells that storage must be cleaned if dirty.

=cut

has clean => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
);

=attr resume

Tells that storage should try to resume from a dirty state:
preserve previous scheduled files and purge unknown ones
before performing a commit.

=cut

has resume => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
);

=attr author

Name of the committing author in local storage.

The name is configured on the storage initialization.

=cut

has author => (
    is => 'ro',
    isa => 'Str',
    default => 'backimap',
);

=attr email

Author email address that will be used along with the author name
as the committing author.

The email is configured on the storage initialization.

=cut

has email => (
    is => 'ro',
    isa => 'Str',
    default => 'backimap@example.org',
);

sub _git_reset {
    shift->reset( { hard => 1 } );
}

subtype 'Git::Wrapper' => as 'Object' => where { $_->isa('Git::Wrapper') };

has _git => (
    is => 'ro',
    isa => 'Git::Wrapper',
    lazy => 1,
    builder => '_build_git',
);

sub _build_git {
    my $self = shift;

    my $dir = $self->dir;
    my $git = Git::Wrapper->new("$dir");

    if ( $self->init ) {
        die "directory $dir already initialized\n"
            if -d $dir->subdir(".git");

        $dir->mkpath();
        $git->init();
        $git->config( "user.name", $self->author );
        $git->config( "user.email", $self->email );
    }

    if ( $git->status->is_dirty ) {
        die "directory $dir is dirty, consider --clean or --resume options\n"
            unless $self->clean or $self->resume;

        my @unknown = map { $_->from } $git->status->get("unknown");

        # --resume takes precedence over --clean
        if ( $self->resume ) {
            for my $file (@unknown) {
                $dir->file($file)->remove();
            }

            eval { $git->commit( { all => 1, message => 'resume previous backup' } ) }
                if $git->status->is_dirty;
        }
        elsif ( $self->clean ) {
            _git_reset($git);

            die "directory $dir has unknown files: @unknown\n"
                if @unknown;
        }
    }

    return $git;
}

=for Pod::Coverage BUILD

=cut

sub BUILD {
    # This makes sure that git repo is properly initialized
    # before returning successfully from new() constructor.

    shift->_git();
}

=method find( $file, ... )

Returns a list of files that are found in storage.

=cut

sub find {
    my $self = shift;

    my @found = grep { -e $self->dir->file($_) } @_;
    return @found;
}

=method list( $dir )

Returns a list of files in a directory from storage.

=cut

sub list {
    my $self = shift;
    my ($dir) = @_;

    $dir = $self->dir->subdir($dir);
    return unless -d $dir;

    my @list = grep !( $_->is_dir() ), $dir->children();

    @list = map { $_->relative($dir) } @list;
    return @list;
}

=method get( $file )

Retrieves file from storage.

=cut

sub get {
    my $self = shift;
    my ($file) = @_;

    return $self->dir->file($file)->slurp();
}

=method put( $file => $content, ... )

Adds files to storage.

=cut

sub put {
    my $self = shift;

    my $op = sub {
        my $self = shift;
        my ( $filename, $content_ref ) = @_;

        my $filepath = $self->dir->file($filename);
        $filepath->dir->mkpath()
            unless -d $filepath->dir;

        my $file = $filepath->openw('w')
            or die "cannot open $filepath: $!";

        $file->print($$content_ref);
        $file->close();
    };

    $self->_put_files( $op, @_ );
}

=method explode( $dir => $content, ... )

Explodes content MIME parts in several files and adds them to storage.

=cut

sub explode {
    my $self = shift;

    my $op = sub {
        my $self = shift;
        my ( $dir, $content_ref ) = @_;

        my $filepath = $self->dir->subdir($dir);
        $filepath->mkpath()
            unless -d $filepath;

        my $parser = MIME::Parser->new();
        $parser->output_dir( Encode::decode( 'UTF-8', $filepath ) );
        $parser->decode_bodies(1);
        $parser->extract_nested_messages(1);
        $parser->extract_uuencode(1);
        $parser->ignore_errors(1);

        my $entity = $parser->parse( IO::Scalar->new($content_ref) );

        my $filename = $filepath->file('__MIME__');
        Storable::nstore( $entity, $filename )
            or die "cannot open $filename: $!";
    };

    $self->_put_files( $op, @_ );
}

sub _put_files {
    my $self = shift;
    my ( $op, %content_for ) = @_;
    my $git = $self->_git;

    for my $filename ( keys %content_for ) {
        $self->$op( $filename, \$content_for{$filename} );
        $git->add($filename);
    }
}

=method delete( $file, ... )

Removes files from storage.

=cut

sub delete {
    my $self = shift;
    my $git = $self->_git;

    my @files = map { "$_" } @_;

    $git->rm(@files)
        if @files;
}

=method move( $from, $to )

Renames or moves files and directories from one place to another in storage.

=cut

sub move {
    my $self = shift;
    my ( $from, $to ) = @_;
    my $git = $self->_git;

    $git->mv( $from, $to );
}

=method commit( $change, [$file] ... )

Commits pending storage actions with a description of change.
If a list of files is provided, only those will be committed.
Otherwise all pending actions will be performed.

=cut

sub commit {
    my $self = shift;
    my $change = shift;
    my $git = $self->_git;

    if (@_) {
        $git->commit( { message => $change }, @_ );
    }
    else {
        $git->commit( { message => $change, all => 1 } );
    }
}

=method reset()

Rolls back any storage actions that were performed but not committed.
Returns storage back to last committed status.

=cut

sub reset {
    _git_reset( shift->_git );
}

# Required methods in status for MooseX::Storage that don't perform any action
# since the storage backend does not support serialization.
=for Pod::Coverage pack unpack

=cut

sub pack   { }
sub unpack { }

1;
