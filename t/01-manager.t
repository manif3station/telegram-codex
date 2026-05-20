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
        listener_start_runner => $args{listener_start_runner},
        listener_start_pid    => $args{listener_start_pid},
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
            CODEX_REAL_BIN                 => '/opt/codex/bin/codex-real',
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
    is(
        $manager->read_text_file( File::Spec->catfile( $plugin_dir, 'scripts', 'telegram_mcp.py' ) ),
        $manager->read_text_file( File::Spec->catfile( $manager->{skill_root}, 'scripts', 'telegram_mcp.py' ) ),
        'install copies the standalone plugin python script from the skill repo instead of embedding it inside Perl',
    );
    my $market_data = decode_json( $manager->read_text_file($marketplace) );
    is( $market_data->{plugins}[0]{name}, 'telegram-codex', 'install registers plugin in marketplace' );
    is( $result->{codex_wrapper}{real_codex_path}, '/opt/codex/bin/codex-real', 'install records the wrapped real codex binary path' );
    my $wrapper_path = $result->{codex_wrapper}{wrapper_path};
    my $dashboard_launcher_path = $result->{codex_wrapper}{dashboard_launcher_path};
    ok( -f $wrapper_path, 'install writes the codex command wrapper into the user PATH' );
    ok( -f $dashboard_launcher_path, 'install writes the dashboard codex launcher' );
    my $wrapper = $manager->read_text_file($wrapper_path);
    my $dashboard_launcher = $manager->read_text_file($dashboard_launcher_path);
    like( $wrapper, qr/exec "\Q$dashboard_launcher_path\E" "\$@"/, 'wrapper hands off into the dashboard codex launcher' );
    like( $wrapper, qr/telegram-codex-managed-codex-wrapper/, 'wrapper is marked as telegram-codex-managed' );
    like( $dashboard_launcher, qr/exec dashboard telegram-codex\.start "\$@"/, 'dashboard launcher hands off into the skill-owned start entrypoint' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            CODEX_REAL_BIN => '/opt/codex/bin/codex-real',
            PATH           => join( q{:}, File::Spec->catdir( $home, '.local', 'bin' ), '/usr/bin' ),
        },
    );
    my $result = $manager->auto_setup;
    is( $result->{mode}, 'auto_setup', 'auto_setup reports its mode' );
    ok( -f File::Spec->catfile( $home, '.local', 'bin', 'codex' ), 'auto_setup provisions the codex wrapper without requiring plugin install' );
    ok( -f File::Spec->catfile( $home, '.developer-dashboard', 'cli', 'codex' ), 'auto_setup provisions the dashboard codex launcher too' );
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
    is( $paths->{pid_file}, File::Spec->catfile( $runtime, 'session-abc', 'listener.pid' ), 'listener_paths stores pid under the session directory' );
    is( $paths->{log_file}, File::Spec->catfile( $runtime, 'session-abc', 'listener.log' ), 'listener_paths stores log under the session directory' );
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
    my $home = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($bin_dir);
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex' );
    _write( $real_codex, "#!/bin/sh\nexit 0\n" );
    chmod 0755, $real_codex or die "Unable to chmod fake codex: $!";
    local $ENV{PATH} = $bin_dir;
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TELEGRAM_BOT_TOKEN => 'token-xyz',
        },
    );
    my $paths = $manager->codex_launcher_paths;
    is( $manager->resolve_real_codex_bin($paths), $real_codex, 'resolve_real_codex_bin detects the current codex binary from PATH' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $wrapper_root = File::Spec->catdir( $home, '.local', 'bin' );
    make_path($wrapper_root);
    my $wrapper_path = File::Spec->catfile( $wrapper_root, 'codex' );
    my $stored_real  = '/opt/codex/bin/codex-real';
    my $runtime_root = File::Spec->catdir( $home, '.telegram-codex' );
    make_path($runtime_root);
    _write( File::Spec->catfile( $runtime_root, '.codex-real-bin' ), "$stored_real\n" );
    _write( $wrapper_path, "#!/bin/sh\n# telegram-codex-managed-codex-wrapper\nexit 0\n" );
    chmod 0755, $wrapper_path or die "Unable to chmod stored wrapper: $!";
    local $ENV{PATH} = $wrapper_root;
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TELEGRAM_BOT_TOKEN => 'token-xyz',
        },
    );
    my $paths = $manager->codex_launcher_paths;
    is( $manager->resolve_real_codex_bin($paths), $stored_real, 'resolve_real_codex_bin falls back to the stored real codex path when PATH resolves the wrapper itself' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $wrapper_root = File::Spec->catdir( $home, '.local', 'bin' );
    make_path($wrapper_root);
    local $ENV{PATH} = $wrapper_root;
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TELEGRAM_BOT_TOKEN => 'token-xyz',
        },
    );
    my $paths = $manager->codex_launcher_paths;
    my $error = eval { $manager->resolve_real_codex_bin($paths); 1 } ? q{} : $@;
    like( $error, qr/Unable to resolve the real codex binary path/, 'resolve_real_codex_bin fails explicitly when no real codex binary path can be found' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TICKET_REF                      => 'DD-276',
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
            TELEGRAM_CODEX_START_CAPTURE    => 1,
            CODEX_REAL_BIN                  => '/opt/codex/bin/codex-real',
        },
    );
    my $plan = $manager->execute_start('--full-auto');
    is( $plan->{action}, 'exec', 'execute_start returns an exec plan when capture mode is enabled' );
    is_deeply( $plan->{codex_args}, ['--full-auto'], 'execute_start preserves direct codex args without a saved session mapping' );
    is( $plan->{start_listener}, 1, 'execute_start enables listener startup when autostart is enabled and a token is available' );
    is( $plan->{listener_session_id}, 'default', 'execute_start falls back to default listener session id when no Codex session is known yet' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $home, '.developer-dashboard', 'config' );
    make_path($config_root);
    _write(
        File::Spec->catfile( $config_root, 'codex.json' ),
        encode_json(
            {
                'DD-276'      => 'session-saved-77',
                _last_action  => 'Add DD-276',
                _last_update  => '2026-05-20 21:00:00',
            }
        ),
    );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TICKET_REF                      => 'DD-276',
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
            CODEX_REAL_BIN                  => '/opt/codex/bin/codex-real',
            TELEGRAM_CODEX_START_CAPTURE    => 1,
        },
    );
    my $plan = $manager->execute_start('--search');
    is_deeply( $plan->{codex_args}, [ 'resume', 'session-saved-77', '--search' ], 'execute_start preserves the original saved-session resume logic from the dashboard codex launcher' );
    is( $plan->{mapped_session}, 'session-saved-77', 'execute_start reports the mapped saved session id' );
    is( $plan->{listener_session_id}, 'session-saved-77', 'execute_start uses the saved session id for listener state when no explicit session id was given' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TICKET_REF                   => 'DD-276',
            CODEX_REAL_BIN               => '/opt/codex/bin/codex-real',
            TELEGRAM_CODEX_START_CAPTURE => 1,
        },
    );
    my $result = $manager->execute_start( 'add', 'session-add-22' );
    is( $result->{action}, 'add', 'execute_start still supports add mode' );
    is( $result->{codex_session}, 'session-add-22', 'execute_start add mode preserves the saved-session management behavior' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $home, '.developer-dashboard', 'config' );
    make_path($config_root);
    _write(
        File::Spec->catfile( $config_root, 'codex.json' ),
        encode_json(
            {
                'DD-276'            => 'session-remove-44',
                'session-remove-44' => 'stale-marker',
            }
        ),
    );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TICKET_REF => 'DD-276',
        },
    );
    my $result = $manager->execute_start('remove');
    is( $result->{action}, 'remove', 'execute_start still supports remove mode' );
    is( $result->{codex_session}, 'session-remove-44', 'execute_start remove mode uses the saved session mapping' );
    my $saved = decode_json( $manager->read_text_file( File::Spec->catfile( $config_root, 'codex.json' ) ) );
    ok( !exists $saved->{'session-remove-44'}, 'execute_start remove mode preserves the original launcher deletion behavior for the saved session key' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $listener_marker = File::Spec->catfile( $home, 'listener-child.log' );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
            TELEGRAM_CODEX_RUNTIME_DIR      => $home,
            CODEX_REAL_BIN                  => '/opt/codex/bin/codex-real',
        },
        listener_start_pid => 424242,
        listener_start_runner => sub {
            my ( $session_id, $paths ) = @_;
            open my $fh, '>>', $listener_marker or die $!;
            print {$fh} "$session_id|$paths->{log_file}\n";
            close $fh or die $!;
        },
    );
    my $paths = $manager->start_listener_if_needed('session-launch-88');
    ok( -f $paths->{pid_file}, 'start_listener_if_needed writes a pid file in the session runtime directory' );
    ok( defined $paths->{log_file} && $paths->{log_file} ne q{}, 'start_listener_if_needed returns the session log path' );
    is( $manager->read_text_file( $paths->{pid_file} ), "424242\n", 'start_listener_if_needed records the provided listener pid in test mode without forking a real listener' );
    my $marker = do {
        open my $fh, '<', $listener_marker or die $!;
        local $/;
        <$fh>;
    };
    like( $marker, qr/session-launch-88/, 'start_listener_if_needed runs the child listener startup path for the requested session' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $home, 'session-running-11' );
    make_path($session_dir);
    _write( File::Spec->catfile( $session_dir, 'listener.pid' ), "$$\n" );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TELEGRAM_CODEX_RUNTIME_DIR => $home,
        },
    );
    my $paths = $manager->start_listener_if_needed('session-running-11');
    is( $paths->{listener_running}, 1, 'start_listener_if_needed leaves an already-running session listener alone' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $home, 'session-stale-11' );
    make_path($session_dir);
    _write( File::Spec->catfile( $session_dir, 'listener.pid' ), "999999\n" );
    my $listener_marker = File::Spec->catfile( $home, 'listener-stale.log' );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TELEGRAM_CODEX_RUNTIME_DIR => $home,
        },
        listener_start_pid => 515151,
        listener_start_runner => sub {
            my ( $session_id ) = @_;
            open my $fh, '>>', $listener_marker or die $!;
            print {$fh} "$session_id\n";
            close $fh or die $!;
        },
    );
    my $paths = $manager->start_listener_if_needed('session-stale-11');
    is( $manager->read_text_file( $paths->{pid_file} ), "515151\n", 'start_listener_if_needed replaces a stale pid file with the new listener pid' );
    my $marker = do {
        open my $fh, '<', $listener_marker or die $!;
        local $/;
        <$fh>;
    };
    is( $marker, "session-stale-11\n", 'start_listener_if_needed relaunches the listener after removing a stale pid file' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($bin_dir);
    my $dashboard_log = File::Spec->catfile( $home, 'dashboard.exec.log' );
    my $dashboard = File::Spec->catfile( $bin_dir, 'dashboard' );
    _write( $dashboard, "#!/bin/sh\nprintf '%s\\n' \"\$@\" > \"$dashboard_log\"\nexit 0\n" );
    chmod 0755, $dashboard or die "Unable to chmod fake dashboard: $!";
    local $ENV{PATH} = $bin_dir;
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            TELEGRAM_CODEX_RUNTIME_DIR => $home,
        },
    );
    my $paths = $manager->start_listener_if_needed('session-forked-22');
    waitpid $paths->{pid}, 0 if $paths->{pid};
    my $exec_log = do {
        open my $fh, '<', $dashboard_log or die $!;
        local $/;
        <$fh>;
    };
    is( $exec_log, "telegram-codex.listen\n", 'start_listener_if_needed can fork and exec an isolated fake dashboard listener command without touching Telegram' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($bin_dir);
    my $args_file = File::Spec->catfile( $home, 'real-codex.args' );
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex-real' );
    _write( $real_codex, "#!/bin/sh\nprintf '%s\\n' \"\$@\" > \"$args_file\"\nexit 0\n" );
    chmod 0755, $real_codex or die "Unable to chmod fake real codex: $!";
    my $pid = fork();
    die "Unable to fork execute_start real-codex test: $!" if !defined $pid;
    if ( !$pid ) {
        my $manager = new_manager(
            cwd  => $home,
            home => $home,
            env  => {
                CODEX_REAL_BIN => $real_codex,
            },
        );
        $manager->execute_start('--search');
        exit 91;
    }
    waitpid $pid, 0;
    is( $? >> 8, 0, 'execute_start execs the real codex binary when no Ollama override is set' );
    my $args = do {
        open my $fh, '<', $args_file or die $!;
        local $/;
        <$fh>;
    };
    is( $args, "--search\n", 'execute_start forwards direct codex args to the real codex binary' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $pid = fork();
    die "Unable to fork execute_start failure test: $!" if !defined $pid;
    if ( !$pid ) {
        my $manager = new_manager(
            cwd  => $home,
            home => $home,
            env  => {
                CODEX_REAL_BIN => File::Spec->catfile( $home, 'definitely-missing-codex' ),
            },
        );
        $manager->execute_start('--search');
        exit 94;
    }
    waitpid $pid, 0;
    isnt( $? >> 8, 94, 'execute_start reaches the post-exec failure path when the real codex binary cannot be launched' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($bin_dir);
    my $args_file = File::Spec->catfile( $home, 'ollama-default.args' );
    my $ollama = File::Spec->catfile( $bin_dir, 'ollama' );
    _write( $ollama, "#!/bin/sh\nprintf '%s\\n' \"\$@\" > \"$args_file\"\nexit 0\n" );
    chmod 0755, $ollama or die "Unable to chmod fake ollama: $!";
    local $ENV{PATH} = $bin_dir;
    my $pid = fork();
    die "Unable to fork execute_start ollama default test: $!" if !defined $pid;
    if ( !$pid ) {
        my $manager = new_manager(
            cwd  => $home,
            home => $home,
            env  => {
                OLLAMA_MODEL  => '2',
                CODEX_REAL_BIN => '/opt/codex/bin/codex-real',
            },
        );
        $manager->execute_start('--search');
        exit 92;
    }
    waitpid $pid, 0;
    is( $? >> 8, 0, 'execute_start supports the OLLAMA_MODEL=2 default-model branch' );
    my $args = do {
        open my $fh, '<', $args_file or die $!;
        local $/;
        <$fh>;
    };
    is( $args, "launch\ncodex\n--model\nqwen3.5:397b-cloud\n", 'execute_start launches the default Ollama model for OLLAMA_MODEL=2' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($bin_dir);
    my $args_file = File::Spec->catfile( $home, 'ollama-custom.args' );
    my $ollama = File::Spec->catfile( $bin_dir, 'ollama' );
    _write( $ollama, "#!/bin/sh\nprintf '%s\\n' \"\$@\" > \"$args_file\"\nexit 0\n" );
    chmod 0755, $ollama or die "Unable to chmod fake ollama: $!";
    local $ENV{PATH} = $bin_dir;
    my $pid = fork();
    die "Unable to fork execute_start ollama custom test: $!" if !defined $pid;
    if ( !$pid ) {
        my $manager = new_manager(
            cwd  => $home,
            home => $home,
            env  => {
                OLLAMA_MODEL  => '1',
                CODEX_REAL_BIN => '/opt/codex/bin/codex-real',
            },
        );
        $manager->execute_start('resume', 'session-x');
        exit 93;
    }
    waitpid $pid, 0;
    is( $? >> 8, 0, 'execute_start supports the OLLAMA_MODEL=1 alias branch' );
    my $args = do {
        open my $fh, '<', $args_file or die $!;
        local $/;
        <$fh>;
    };
    is( $args, "launch\ncodex\n--model\nqwen3.5:397b-cloud\n--\nresume\nsession-x\n", 'execute_start expands OLLAMA_MODEL=1 to the default model and preserves codex args' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $local_bin = File::Spec->catdir( $home, '.local', 'bin' );
    my $home_bin  = File::Spec->catdir( $home, 'bin' );
    make_path($local_bin);
    make_path($home_bin);
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            PATH => join( q{:}, $home_bin, $local_bin, '/usr/bin' ),
        },
    );
    is( $manager->select_codex_wrapper_dir, $home_bin, 'select_codex_wrapper_dir uses the first supported user PATH directory' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $local_bin = File::Spec->catdir( $home, '.local', 'bin' );
    my $home_bin  = File::Spec->catdir( $home, 'bin' );
    make_path($local_bin);
    make_path($home_bin);
    _write( File::Spec->catfile( $local_bin, 'codex' ), "#!/bin/sh\nexit 0\n" );
    _write( File::Spec->catfile( $home_bin,  'codex' ), "#!/bin/sh\nexit 0\n" );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            PATH => join( q{:}, $local_bin, $home_bin, '/usr/bin' ),
        },
    );
    is( $manager->select_codex_wrapper_dir, $local_bin, 'select_codex_wrapper_dir falls back to the first supported candidate when all supported codex paths already exist' );
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
    my @get_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-rate-limited',
        },
        get_runner => sub {
            my ( $method, $params ) = @_;
            push @get_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 55,
                        message   => {
                            message_id => 21,
                            text       => 'hello',
                            chat       => { id => 88, type => 'private' },
                        },
                    },
                ],
            } if @get_calls == 1;
            return { ok => JSON::XS::true, result => [] };
        },
        post_runner => sub {
            die "Telegram POST failed for sendMessage: 429 Too Many Requests\n";
        },
    );
    my $result = $manager->execute_listen( 2, 0, 'listener ack' );
    is( $result->{processed}, 1, 'listen still records inbound messages when reply send fails' );
    is( $result->{replied}, 0, 'listen does not count failed reply sends as successful replies' );
    is( scalar @{ $result->{reply_errors} }, 1, 'listen reports reply-send failures instead of dying before state is saved' );
    is( $manager->read_text_file( $result->{offset_file} ), "56\n", 'listen still persists the next offset after a reply-send failure so the same message is not retried forever' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @get_calls;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN                   => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR           => $runtime,
            CODEX_SESSION_ID                     => 'session-prime-latest',
            TELEGRAM_CODEX_LISTENER_PRIME_LATEST => '1',
        },
        get_runner => sub {
            my ( $method, $params ) = @_;
            push @get_calls, [ $method, { %{$params} } ];
            return {
                ok     => JSON::XS::true,
                result => !defined $params->{offset}
                  ? [
                        { update_id => 90, message => { message_id => 1, text => 'old one', chat => { id => 88, type => 'private' } } },
                        { update_id => 91, message => { message_id => 2, text => 'old two', chat => { id => 88, type => 'private' } } },
                    ]
                  : [],
            };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return { ok => JSON::XS::true, result => { message_id => 1 } };
        },
    );
    my $result = $manager->execute_listen( 1, 0 );
    is( $result->{processed}, 0, 'prime-latest auto-start does not process old backlog messages on the first cycle' );
    is( $result->{replied}, 0, 'prime-latest auto-start does not reply to old backlog messages' );
    is( $manager->read_text_file( $result->{offset_file} ), "92\n", 'prime-latest auto-start persists the primed next offset' );
    is( scalar @post_calls, 0, 'prime-latest auto-start does not send message replies for old backlog items' );
    is_deeply( $get_calls[0][1], { limit => 100, timeout => 0 }, 'prime-latest auto-start first scans the pending Telegram backlog without an offset' );
    is_deeply( $get_calls[1][1], { limit => 20, timeout => 0, offset => 92 }, 'prime-latest auto-start begins normal listening from the primed offset' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @get_calls;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN                   => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR           => $runtime,
            CODEX_SESSION_ID                     => 'session-prime-then-reply',
            TELEGRAM_CODEX_LISTENER_PRIME_LATEST => '1',
        },
        get_runner => sub {
            my ( $method, $params ) = @_;
            push @get_calls, [ $method, { %{$params} } ];
            return {
                ok     => JSON::XS::true,
                result => !defined $params->{offset}
                  ? [
                        { update_id => 100, message => { message_id => 1, text => 'old one', chat => { id => 88, type => 'private' } } },
                        { update_id => 101, message => { message_id => 2, text => 'old two', chat => { id => 88, type => 'private' } } },
                    ]
                  : [
                        { update_id => 102, message => { message_id => 3, text => 'new one', chat => { id => 88, type => 'private' } } },
                    ],
            };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return { ok => JSON::XS::true, result => { message_id => 200 } };
        },
    );
    my $result = $manager->execute_listen( 1, 0 );
    is( $result->{processed}, 1, 'prime-latest auto-start still processes new messages after priming the old backlog away' );
    is( $result->{replied}, 1, 'prime-latest auto-start still replies to new messages after priming' );
    is( $manager->read_text_file( $result->{offset_file} ), "103\n", 'prime-latest auto-start advances offset after the new message cycle' );
    is_deeply(
        $post_calls[0][1],
        {
            chat_id             => 88,
            text                => 'telegram-codex listener is live. Your message was received and queued for Codex.',
            reply_to_message_id => 3,
        },
        'prime-latest auto-start replies only to the first truly new message after priming',
    );
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
