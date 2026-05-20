#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::XS qw(decode_json encode_json);
use Test::More;

use lib 'lib';
use Telegram::Codex::Manager;

{
    package TestResponse;
    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub is_success      { return shift->{is_success} }
    sub decoded_content { return shift->{decoded_content} }
    sub status_line     { return shift->{status_line} || '500 fail' }
}

{
    package TestUA;
    sub new {
        my ( $class, %args ) = @_;
        return bless {
            request_queue => $args{request_queue} || [],
            get_queue     => $args{get_queue} || [],
        }, $class;
    }
    sub request {
        my ( $self, $request ) = @_;
        push @{ $self->{requests} }, $request;
        return shift @{ $self->{request_queue} };
    }
    sub get {
        my ( $self, @args ) = @_;
        push @{ $self->{gets} }, \@args;
        return shift @{ $self->{get_queue} };
    }
}

sub new_manager {
    my (%args) = @_;
    my $cwd = $args{cwd} || tempdir( CLEANUP => 1 );
    return Telegram::Codex::Manager->new(
        cwd             => $cwd,
        home            => $args{home} || $cwd,
        skill_root      => $args{skill_root},
        env             => $args{env} || {},
        get_runner      => $args{get_runner},
        post_runner     => $args{post_runner},
        download_runner => $args{download_runner},
    );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $marketplace = File::Spec->catfile( $home, '.codex', '.tmp', 'plugins', '.agents', 'plugins', 'marketplace.json' );
    make_path( File::Spec->catdir( $home, '.codex', '.tmp', 'plugins', '.agents', 'plugins' ) );
    my $manager = new_manager(
        home => $home,
        env  => {
            CODEX_PRIMARY_PLUGIN_ROOT      => '~/.codex/.tmp/plugins/plugins',
            CODEX_PRIMARY_MARKETPLACE_PATH => '~/.codex/.tmp/plugins/.agents/plugins/marketplace.json',
            TELEGRAM_BOT_TOKEN             => 'token-123',
        },
    );
    my $result = $manager->execute_install('token-123');
    is( $result->{plugin}, 'telegram-codex', 'install returns plugin name' );
    my $plugin_dir = File::Spec->catdir( $home, '.codex', '.tmp', 'plugins', 'plugins', 'telegram-codex' );
    ok( -f File::Spec->catfile( $plugin_dir, '.codex-plugin', 'plugin.json' ), 'install writes plugin manifest' );
    ok( -f File::Spec->catfile( $plugin_dir, '.mcp.json' ), 'install writes mcp config' );
    ok( -f File::Spec->catfile( $plugin_dir, '.env' ), 'install writes plugin env file' );
    ok( -f File::Spec->catfile( $plugin_dir, 'scripts', 'telegram_mcp.py' ), 'install writes mcp server script' );
    my $market_data = decode_json( $manager->read_text_file($marketplace) );
    is( $market_data->{plugins}[0]{name}, 'telegram-codex', 'install registers plugin in marketplace' );
}

{
    my $manager = new_manager(
        env        => { TELEGRAM_BOT_TOKEN => 'token-xyz' },
        get_runner => sub {
            my ( $method, $params ) = @_;
            is( $method, 'getMe', 'get-me uses Telegram getMe' );
            is_deeply( $params, {}, 'get-me sends no params' );
            return {
                ok     => JSON::XS::true,
                result => { username => 'jamesthexe_bot', first_name => 'James (Executor)' },
            };
        },
    );
    my $result = $manager->execute_get_me;
    is( $result->{username}, 'jamesthexe_bot', 'get-me returns bot username' );
}

{
    my $manager = new_manager(
        env        => { TELEGRAM_BOT_TOKEN => 'token-xyz' },
        get_runner => sub {
            my ( $method, $params ) = @_;
            is( $method, 'getUpdates', 'updates uses getUpdates' );
            is_deeply( $params, { offset => 10, limit => 5, timeout => 0 }, 'updates forwards optional parameters' );
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 91,
                        message   => {
                            message_id => 7,
                            text       => 'hello',
                            chat       => { id => 99, type => 'private' },
                            photo      => [ { file_id => 'small' }, { file_id => 'big' } ],
                            document   => { file_id => 'doc-1', file_name => 'report.pdf' },
                        },
                    },
                ],
            };
        },
    );
    my $result = $manager->execute_updates( 10, 5, 0 );
    is( $result->{count}, 1, 'updates returns count' );
    is( $result->{updates}[0]{photo}{file_id}, 'big', 'updates keeps the largest photo' );
    is( $result->{updates}[0]{document}{file_name}, 'report.pdf', 'updates returns document metadata' );
    is( $result->{next_offset}, 92, 'updates returns next offset' );
}

{
    my $cwd = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd             => $cwd,
        env             => { TELEGRAM_BOT_TOKEN => 'token-xyz' },
        get_runner      => sub {
            my ( $method, $params ) = @_;
            is( $method, 'getFile', 'download first resolves getFile' );
            is( $params->{file_id}, 'file-123', 'download forwards file id' );
            return { ok => JSON::XS::true, result => { file_path => 'documents/report.pdf' } };
        },
        download_runner => sub {
            my ($url) = @_;
            like( $url, qr{/documents/report\.pdf$}, 'download fetches telegram file path' );
            return 'PDFDATA';
        },
    );
    my $result = $manager->execute_download('file-123');
    ok( -f File::Spec->catfile( $cwd, 'downloads', 'report.pdf' ), 'download writes file locally' );
    is( $result->{bytes}, 7, 'download reports byte length' );
}

{
    my @calls;
    my $manager = new_manager(
        env         => { TELEGRAM_BOT_TOKEN => 'token-xyz' },
        post_runner => sub {
            my ( $method, $params, $files ) = @_;
            push @calls, [ $method, $params, $files ];
            return { ok => JSON::XS::true, result => { message_id => 12, chat => { id => $params->{chat_id} }, text => $params->{text}, caption => $params->{caption} } };
        },
    );
    my $reply = $manager->execute_reply( 55, 'hello', 'there' );
    is( $reply->{text}, 'hello there', 'reply joins trailing text arguments' );
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $photo = File::Spec->catfile( $tmpdir, 'photo.png' );
    my $doc = File::Spec->catfile( $tmpdir, 'note.txt' );
    _write( $photo, 'png' );
    _write( $doc, 'doc' );
    $manager->execute_send_photo( 55, $photo, 'look', 'here' );
    $manager->execute_send_document( 55, $doc, 'read', 'this' );
    is( $calls[1][0], 'sendPhoto', 'send-photo uses sendPhoto' );
    is( $calls[1][2]{photo}, $photo, 'send-photo forwards file path to multipart helper' );
    is( $calls[2][0], 'sendDocument', 'send-document uses sendDocument' );
    is( $calls[2][2]{document}, $doc, 'send-document forwards file path to multipart helper' );
}

{
    my @post_calls;
    my @get_calls;
    my $manager = new_manager(
        env         => { TELEGRAM_BOT_TOKEN => 'token-xyz' },
        get_runner  => sub {
            my ( $method, $params ) = @_;
            push @get_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => [
                    { update_id => 10, message => { message_id => 5, text => '/start', chat => { id => 88 } } },
                    { update_id => 11, message => { message_id => 6, text => 'not-start', chat => { id => 88 } } },
                ],
            };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return { ok => JSON::XS::true, result => { message_id => 22, chat => { id => $params->{chat_id} } } };
        },
    );
    my $result = $manager->execute_auto_reply_start;
    is( $result->{checked}, 2, 'auto-reply-start inspects recent updates' );
    is( scalar @{ $result->{replied} }, 1, 'auto-reply-start replies once for /start' );
    is( $post_calls[0][0], 'sendMessage', 'auto-reply-start sends a message reply' );
    is( $get_calls[-1][1]{offset}, 12, 'auto-reply-start acknowledges updates with next offset' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-abc',
        },
    );
    my $paths = $manager->listener_paths;
    is( $paths->{runtime_dir}, File::Spec->catdir( $runtime, 'session-abc' ), 'listener_paths partitions runtime state by CODEX_SESSION_ID' );
    is( $paths->{offset_file}, File::Spec->catfile( $runtime, 'session-abc', 'listener.offset' ), 'listener_paths stores offset under the session directory' );
    is( $paths->{inbox_file}, File::Spec->catfile( $runtime, 'session-abc', 'listener.inbox.jsonl' ), 'listener_paths stores inbox ledger under the session directory' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN           => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR   => $runtime,
            TELEGRAM_CODEX_SESSION_ID    => 'session-explicit',
            CODEX_SESSION_ID             => 'session-ignored',
        },
    );
    my $paths = $manager->listener_paths;
    is( $paths->{runtime_dir}, File::Spec->catdir( $runtime, 'session-explicit' ), 'listener_paths prefers TELEGRAM_CODEX_SESSION_ID when both session variables exist' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @get_calls;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-listen',
        },
        get_runner => sub {
            my ( $method, $params ) = @_;
            push @get_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 30,
                        message   => {
                            message_id => 10,
                            text       => 'hello',
                            chat       => { id => 88, type => 'private' },
                        },
                    },
                    {
                        update_id => 31,
                        message   => {
                            message_id => 11,
                            chat       => { id => 88, type => 'private' },
                            document   => { file_id => 'doc-9', file_name => 'report.pdf' },
                        },
                    },
                ],
            } if @get_calls == 1;
            return { ok => JSON::XS::true, result => [] };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 200 + scalar @post_calls, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $result = $manager->execute_listen( 2, 0, 'listener ack' );
    is( $result->{cycles}, 2, 'listen reports executed cycles' );
    is( $result->{processed}, 2, 'listen processes inbound updates' );
    is( $result->{replied}, 2, 'listen auto-replies to eligible messages' );
    is( $result->{next_offset}, 32, 'listen reports next offset' );
    is( $get_calls[0][1]{timeout}, 0, 'listen forwards poll timeout' );
    ok( !exists $get_calls[0][1]{offset}, 'listen omits offset before state exists' );
    is( $get_calls[1][1]{offset}, 32, 'listen resumes from persisted next offset on the next cycle' );
    is( scalar @post_calls, 2, 'listen sends a reply per eligible inbound message' );
    is( $post_calls[0][1]{reply_to_message_id}, 10, 'listen replies to original text message id' );
    is( $post_calls[1][1]{reply_to_message_id}, 11, 'listen replies to original document message id' );
    my $offset_file = File::Spec->catfile( $runtime, 'session-listen', 'listener.offset' );
    my $inbox_file  = File::Spec->catfile( $runtime, 'session-listen', 'listener.inbox.jsonl' );
    is( $manager->read_text_file($offset_file), "32\n", 'listen persists next offset to runtime state' );
    my @entries = split /\n/, $manager->read_text_file($inbox_file);
    is( scalar @entries, 2, 'listen appends inbound messages to inbox ledger' );
    is( decode_json( $entries[1] )->{document}{file_name}, 'report.pdf', 'listen logs document metadata in inbox ledger' );
    is( $result->{offset_file}, $offset_file, 'listen reports the session-specific offset path' );
    is( $result->{inbox_file}, $inbox_file, 'listen reports the session-specific inbox path' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $runtime, 'session-resume' );
    mkdir $session_dir;
    _write( File::Spec->catfile( $session_dir, 'listener.offset' ), "50\n" );
    my @get_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-resume',
        },
        get_runner => sub {
            my ( $method, $params ) = @_;
            push @get_calls, [ $method, $params ];
            return { ok => JSON::XS::true, result => [] };
        },
        post_runner => sub {
            die 'listen should not reply when no new updates are present';
        },
    );
    my $result = $manager->execute_listen( 1, 0, 'listener ack' );
    is( $result->{processed}, 0, 'listen handles empty cycles cleanly' );
    is( $get_calls[0][1]{offset}, 50, 'listen resumes from stored offset on restart' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-no-reply',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 77,
                        message   => {
                            message_id => 12,
                            chat       => { id => 88, type => 'private' },
                        },
                    },
                ],
            };
        },
        post_runner => sub {
            push @post_calls, [@_];
            return { ok => JSON::XS::true, result => { message_id => 1, chat => { id => 88 } } };
        },
    );
    my $result = $manager->execute_listen( 1, 0, 'listener ack' );
    is( $result->{processed}, 1, 'listen still logs non-replied updates' );
    is( scalar @post_calls, 0, 'listen skips auto-reply for unsupported message kinds' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-media',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 81,
                        message   => {
                            message_id => 13,
                            chat       => { id => 88, type => 'private' },
                            audio      => { file_id => 'audio-2' },
                        },
                    },
                    {
                        update_id => 82,
                        message   => {
                            message_id => 14,
                            chat       => { id => 88, type => 'private' },
                            video      => { file_id => 'video-2' },
                        },
                    },
                    {
                        update_id => 83,
                        message   => {
                            message_id => 15,
                            chat       => { id => 88, type => 'private' },
                            voice      => { file_id => 'voice-2' },
                        },
                    },
                ],
            };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return { ok => JSON::XS::true, result => { message_id => 50 + scalar @post_calls, chat => { id => $params->{chat_id} } } };
        },
    );
    my $result = $manager->execute_listen( 1, 0, 'listener ack' );
    is( $result->{processed}, 3, 'listen processes audio, video, and voice updates' );
    is( scalar @post_calls, 3, 'listen replies to audio, video, and voice updates' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        home => $home,
        env  => {
            CODEX_PRIMARY_PLUGIN_ROOT         => '~/primary/plugins',
            CODEX_PRIMARY_MARKETPLACE_PATH    => '~/primary/marketplace.json',
            CODEX_MIRROR_PLUGIN_ROOT          => '~/mirror/plugins',
            CODEX_MIRROR_MARKETPLACE_PATH     => '~/mirror/marketplace.json',
        },
    );
    make_path( File::Spec->catdir( $home, 'mirror' ) );
    my @targets = $manager->plugin_targets;
    is( scalar @targets, 2, 'plugin targets include mirror path when mirror base exists' );
}

{
    my $cwd = tempdir( CLEANUP => 1 );
    _write(
        File::Spec->catfile( $cwd, '.env' ),
        "TELEGRAM_BOT_TOKEN=file-token\nKEEP=value\n",
    );
    local $ENV{TELEGRAM_BOT_TOKEN} = q{};
    my $manager = Telegram::Codex::Manager->new(
        cwd  => $cwd,
        home => '/tmp/test-home',
    );
    is( $manager->env_value('KEEP'), 'value', 'merged env loads values from local .env file' );
    is( $manager->resolve_token(), 'file-token', 'resolve_token falls back to loaded .env token' );
    is( $manager->resolve_path(undef), undef, 'resolve_path preserves undefined value' );
    is( $manager->resolve_path('~'), '/tmp/test-home', 'resolve_path expands bare tilde to home' );
    is( $manager->resolve_path('relative/path.txt'), 'relative/path.txt', 'resolve_path leaves plain paths unchanged' );
    is( $manager->basename('dir\\file.txt'), 'file.txt', 'basename normalizes windows separators' );
}

{
    my $root = tempdir( CLEANUP => 1 );
    my $project = File::Spec->catdir( $root, 'project', 'app' );
    make_path($project);
    _write( File::Spec->catfile( $root, '.env' ), "TELEGRAM_BOT_TOKEN=root-token\n" );
    local $ENV{TELEGRAM_BOT_TOKEN} = q{};
    my $manager = Telegram::Codex::Manager->new(
        cwd  => $project,
        home => $root,
    );
    is( $manager->resolve_token(), 'root-token', 'resolve_token discovers TELEGRAM_BOT_TOKEN from a parent project .env' );
}

{
    my $root = tempdir( CLEANUP => 1 );
    my $project = File::Spec->catdir( $root, 'project' );
    my $skill_root = File::Spec->catdir( $root, 'skill-root' );
    make_path($project);
    make_path($skill_root);
    _write( File::Spec->catfile( $skill_root, '.env' ), "TELEGRAM_BOT_TOKEN=skill-token\n" );
    local $ENV{TELEGRAM_BOT_TOKEN} = q{};
    my $manager = Telegram::Codex::Manager->new(
        cwd        => $project,
        home       => $root,
        skill_root => $skill_root,
    );
    is( $manager->resolve_token(), 'skill-token', 'resolve_token falls back to skill-level .env when project .env is absent' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $doc = File::Spec->catfile( $tmpdir, 'doc.txt' );
    _write( $doc, 'document' );
    my $ua = TestUA->new(
        request_queue => [
            TestResponse->new(
                is_success      => 1,
                decoded_content => encode_json( { ok => JSON::XS::true, result => { id => 1 } } ),
            ),
            TestResponse->new(
                is_success      => 1,
                decoded_content => encode_json( { ok => JSON::XS::true, result => { sent => JSON::XS::true } } ),
            ),
            TestResponse->new(
                is_success      => 1,
                decoded_content => encode_json( { ok => JSON::XS::true, result => { uploaded => JSON::XS::true } } ),
            ),
        ],
        get_queue => [
            TestResponse->new(
                is_success      => 1,
                decoded_content => 'FILEDATA',
            ),
        ],
    );
    my $manager = Telegram::Codex::Manager->new(
        cwd  => $tmpdir,
        home => '/tmp/test-home',
        env  => { TELEGRAM_BOT_TOKEN => 'abc123' },
        ua   => $ua,
    );
    is( $manager->telegram_api_base, 'https://api.telegram.org/botabc123', 'telegram_api_base builds bot API root' );
    is( $manager->telegram_file_base, 'https://api.telegram.org/file/botabc123', 'telegram_file_base builds file API root' );
    is( $manager->telegram_get('getMe')->{result}{id}, 1, 'telegram_get uses UA request path' );
    is( $manager->telegram_post( 'sendMessage', { chat_id => 9 } )->{result}{sent}, 1, 'telegram_post uses UA request path' );
    is( $manager->telegram_post_file( 'sendDocument', { chat_id => 9 }, { document => $doc } )->{result}{uploaded}, 1, 'telegram_post_file uses multipart request path' );
    is( $manager->telegram_download('files/doc.txt'), 'FILEDATA', 'telegram_download uses UA get path' );
    is( $ua->{requests}[0]->method, 'GET', 'telegram_get sends GET request' );
    is( $ua->{requests}[1]->method, 'POST', 'telegram_post sends POST request' );
    is( $ua->{requests}[2]->method, 'POST', 'telegram_post_file sends multipart POST request' );
    like( $ua->{gets}[0][0], qr{/file/botabc123/files/doc\.txt$}, 'telegram_download fetches file URL' );
}

{
    my $cwd = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $cwd,
        home => $cwd,
        env  => { TELEGRAM_BOT_TOKEN => 'token-xyz' },
    );
    my $marketplace = File::Spec->catfile( $cwd, 'marketplace.json' );
    _write(
        $marketplace,
        encode_json(
            {
                name      => 'local-plugins',
                interface => { displayName => 'Local plugins' },
                plugins   => [
                    {
                        name     => 'telegram-codex',
                        source   => { source => 'local', path => './plugins/old' },
                        policy   => { installation => 'HIDDEN', authentication => 'NONE' },
                        category => 'Old',
                    },
                    {
                        name   => 'another-plugin',
                        source => { source => 'local', path => './plugins/another' },
                    },
                ],
            }
        ),
    );
    $manager->update_marketplace($marketplace);
    my $updated = decode_json( $manager->read_text_file($marketplace) );
    is( scalar @{ $updated->{plugins} }, 2, 'update_marketplace updates existing entry without duplication' );
    is( $updated->{plugins}[0]{source}{path}, './plugins/telegram-codex', 'update_marketplace refreshes existing telegram-codex entry' );
    is( $updated->{plugins}[1]{name}, 'another-plugin', 'update_marketplace keeps unrelated plugins' );
}

sub _write {
    my ( $file, $content ) = @_;
    open my $fh, '>', $file or die "Unable to write $file: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $file: $!";
}

done_testing;
