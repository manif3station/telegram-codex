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
    my %env = (
        TELEGRAM_CODEX_DISABLE_PAIRING => 1,
        %{ $args{env} || {} },
    );
    return Telegram::Codex::Manager->new(
        cwd             => $cwd,
        home            => $args{home} || $cwd,
        skill_root      => $args{skill_root},
        env             => \%env,
        get_runner      => $args{get_runner},
        post_runner     => $args{post_runner},
        download_runner => $args{download_runner},
        listener_start_runner => $args{listener_start_runner},
        listener_start_pid    => $args{listener_start_pid},
        sleep_runner         => $args{sleep_runner},
        codex_resume_runner  => $args{codex_resume_runner},
        codex_version_runner => $args{codex_version_runner},
        command_runner       => $args{command_runner},
        pid_check_runner     => $args{pid_check_runner},
        process_signal_runner => $args{process_signal_runner},
        typing_guard_runner  => $args{typing_guard_runner},
        progress_guard_runner => $args{progress_guard_runner},
        fork_runner          => $args{fork_runner},
        process_list_runner  => $args{process_list_runner},
        tmux_panes_runner    => $args{tmux_panes_runner},
        tmux_send_runner     => $args{tmux_send_runner},
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
    my $audio = File::Spec->catfile( $tmpdir, 'sound.mp3' );
    my $doc = File::Spec->catfile( $tmpdir, 'note.txt' );
    _write( $photo, 'png' );
    _write( $audio, 'mp3' );
    _write( $doc, 'doc' );
    $manager->execute_send_photo( 55, $photo, 'look', 'here' );
    $manager->execute_send_audio( 55, $audio, 'listen', 'here' );
    $manager->execute_send_document( 55, $doc, 'read', 'this' );
    is( $calls[1][0], 'sendPhoto', 'send-photo uses sendPhoto' );
    is( $calls[1][2]{photo}, $photo, 'send-photo forwards file path to multipart helper' );
    is( $calls[2][0], 'sendAudio', 'send-audio uses sendAudio' );
    is( $calls[2][2]{audio}, $audio, 'send-audio forwards file path to multipart helper' );
    is( $calls[3][0], 'sendDocument', 'send-document uses sendDocument' );
    is( $calls[3][2]{document}, $doc, 'send-document forwards file path to multipart helper' );
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
    is( $paths->{target_session_file}, File::Spec->catfile( $runtime, 'session-abc', 'codex.session' ), 'listener_paths stores the Codex target session under the session directory' );
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
    is( $plan->{start_collector}, 1, 'execute_start enables collector startup when autostart is enabled and a token is available' );
    is( $plan->{collector_session_id}, $manager->workspace_session_id, 'execute_start derives the collector session id from the workspace when no session env is present' );
    is( $plan->{collector_name}, 'telegram-codex-' . $manager->workspace_session_id, 'execute_start plans the DD collector name for the workspace session' );
    is( $plan->{collector_command}, 'dashboard telegram-codex.check-message ' . $manager->workspace_session_id, 'execute_start plans the session-suffixed collector command' );
    is( $plan->{codex_session_id}, $manager->workspace_session_id, 'execute_start plans Codex replies against the workspace session when nothing is mapped yet' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => File::Spec->catdir( $home, 'mt5-ai' ),
        home => $home,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
            TELEGRAM_CODEX_START_CAPTURE    => 1,
            CODEX_REAL_BIN                  => '/opt/codex/bin/codex-real',
            CODEX_SESSION_ID                => 'skills',
        },
    );
    my $plan = $manager->execute_start;
    is( $plan->{workspace_session_id}, 'mt5-ai', 'execute_start derives the workspace session id from the current workspace name' );
    is( $plan->{collector_session_id}, 'mt5-ai', 'execute_start ignores ambient CODEX_SESSION_ID for collector ownership' );
    is( $plan->{codex_session_id}, 'mt5-ai', 'execute_start keeps the default Codex target aligned to the workspace session when there is no saved mapping' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my @commands;
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            VERSION                         => '0.24',
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
            TELEGRAM_CODEX_START_CAPTURE    => 1,
            CODEX_REAL_BIN                  => '/opt/codex/bin/codex-real',
        },
        command_runner => sub {
            my ($command) = @_;
            push @commands, [@$command];
            return { ok => 1 };
        },
    );
    my $result = $manager->execute_start('--version');
    is( $result->{mode}, 'start', 'execute_start --version reports start mode metadata' );
    is( $result->{action}, 'version', 'execute_start --version is a pure version query' );
    is( $result->{version}, '0.24', 'execute_start --version reports the skill version from env state' );
    ok( !exists $result->{collector_name}, 'execute_start --version does not build collector startup plan data' );
    is_deeply( \@commands, [], 'execute_start --version does not touch dashboard collector orchestration' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            VERSION => '0.25',
        },
        codex_version_runner => sub { return "codex-cli 0.132.0\n"; },
    );
    is( $manager->real_codex_version_output, "codex-cli 0.132.0\n", 'real_codex_version_output can proxy the underlying Codex CLI version string' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin = File::Spec->catfile( $home, 'codex-real-version' );
    _write( $bin, "#!/bin/sh\nprintf 'codex-cli 0.132.0\\n'\n" );
    chmod 0755, $bin or die "Unable to chmod fake codex version binary: $!";
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            CODEX_REAL_BIN => $bin,
        },
    );
    is( $manager->real_codex_version_output, "codex-cli 0.132.0\n", 'real_codex_version_output can read the real Codex binary version output through the subprocess path' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin = File::Spec->catfile( $home, 'codex-real-empty-version' );
    _write( $bin, "#!/bin/sh\nexit 0\n" );
    chmod 0755, $bin or die "Unable to chmod fake empty codex version binary: $!";
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        env  => {
            CODEX_REAL_BIN => $bin,
        },
    );
    my $error = eval { $manager->real_codex_version_output; 1 } ? q{} : $@;
    like( $error, qr/Unexpected empty version output/, 'real_codex_version_output fails explicitly when the real Codex binary prints no version output' );
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
    is( $plan->{collector_session_id}, $manager->workspace_session_id, 'execute_start still keeps the collector session keyed to the workspace session' );
    is( $plan->{codex_session_id}, 'session-saved-77', 'execute_start keeps Telegram replies pointed at the saved Codex session mapping' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $home, '.developer-dashboard', 'config' );
    make_path($config_root);
    _write(
        File::Spec->catfile( $config_root, 'codex.json' ),
        encode_json(
            {
                mt5         => 'session-saved-88',
                _last_action => 'Add mt5',
                _last_update => '2026-05-21 19:00:00',
            }
        ),
    );
    my $workspace = File::Spec->catdir( $home, 'mt5-ai' );
    make_path($workspace);
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
        env  => {
            TICKET_REF                      => 'mt5',
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
            TELEGRAM_CODEX_START_CAPTURE    => 1,
            CODEX_REAL_BIN                  => '/opt/codex/bin/codex-real',
        },
    );
    my $plan = $manager->execute_start( '--profile', 'ollama-launch', '-m', 'qwen3.5:397b-cloud', 'resume', 'session-saved-88' );
    is_deeply(
        $plan->{codex_args},
        [ '--profile', 'ollama-launch', '-m', 'qwen3.5:397b-cloud', 'resume', 'session-saved-88' ],
        'execute_start does not prepend another resume target when the incoming codex argv already carries one',
    );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $home, '.developer-dashboard', 'config' );
    make_path($config_root);
    _write(
        File::Spec->catfile( $config_root, 'config.json' ),
        encode_json(
            {
                collectors => [
                    { name => 'keep-me', interval => 10 },
                    { name => 'telegram-codex-demo', interval => 99, mode => 'multiple' },
                    { name => 'telegram-codex-demo', interval => 1, command => 'bad' },
                ],
            }
        ),
    );
    my $workspace = File::Spec->catdir( $home, 'demo' );
    make_path($workspace);
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
    );
    my $result = $manager->ensure_collector_config( 'demo', cwd => $workspace );
    is( $result->{collector_name}, 'telegram-codex-demo', 'ensure_collector_config targets the expected collector name' );
    is( $result->{removed_duplicates}, 1, 'ensure_collector_config removes duplicate collector entries for the same session' );
    my $saved = decode_json( $manager->read_text_file( File::Spec->catfile( $config_root, 'config.json' ) ) );
    my @telegram_collectors = grep { ref($_) eq 'HASH' && $_->{name} eq 'telegram-codex-demo' } @{ $saved->{collectors} };
    is( scalar @telegram_collectors, 1, 'ensure_collector_config leaves exactly one collector entry for the session' );
    is_deeply(
        $telegram_collectors[0],
        {
            name     => 'telegram-codex-demo',
            interval => 5,
            rotation => { lines => 100 },
            cwd      => $workspace,
            command  => 'dashboard telegram-codex.check-message demo',
            mode     => 'singleton',
        },
        'ensure_collector_config rewrites the collector to the governed telegram-codex collector shape',
    );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $home, '.developer-dashboard', 'config' );
    make_path($config_root);
    _write(
        File::Spec->catfile( $config_root, 'config.json' ),
        encode_json(
            {
                collectors => [
                    {
                        name     => 'telegram-codex-cwd-demo',
                        interval => 5,
                        rotation => { lines => 100 },
                        cwd      => '/tmp/old-workspace',
                        command  => 'dashboard telegram-codex.check-messages',
                        mode     => 'singleton',
                    },
                ],
            }
        ),
    );
    my $workspace = File::Spec->catdir( $home, 'new-workspace' );
    make_path($workspace);
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
    );
    my $result = $manager->ensure_collector_config( 'cwd-demo', cwd => $workspace );
    is( $result->{created}, 0, 'ensure_collector_config treats a same-name collector with the wrong cwd as an update, not a new collector' );
    my $saved = decode_json( $manager->read_text_file( File::Spec->catfile( $config_root, 'config.json' ) ) );
    is( $saved->{collectors}[0]{cwd}, $workspace, 'ensure_collector_config rewrites collector cwd when the existing entry points at a different workspace' );
    is( $saved->{collectors}[0]{command}, 'dashboard telegram-codex.check-message cwd-demo', 'ensure_collector_config rewrites the legacy plural collector command to the session-suffixed check-message form' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $home, '.developer-dashboard', 'config' );
    make_path($config_root);
    my $workspace = File::Spec->catdir( $home, 'mt5-ai' );
    make_path($workspace);
    _write(
        File::Spec->catfile( $config_root, 'config.json' ),
        encode_json(
            {
                collectors => [
                    {
                        name     => 'telegram-codex-skills',
                        interval => 5,
                        rotation => { lines => 100 },
                        cwd      => $workspace,
                        command  => 'dashboard telegram-codex.check-message skills',
                        mode     => 'singleton',
                    },
                    {
                        name     => 'telegram-codex-mt5-ai',
                        interval => 5,
                        rotation => { lines => 100 },
                        cwd      => $workspace,
                        command  => 'dashboard telegram-codex.check-message mt5-ai',
                        mode     => 'singleton',
                    },
                ],
            }
        ),
    );
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
    );
    my $result = $manager->ensure_collector_config( 'mt5-ai', cwd => $workspace );
    is( $result->{removed_workspace_conflicts}, 1, 'ensure_collector_config removes stale telegram-codex collectors that still target the same workspace under the wrong session id' );
    my $saved = decode_json( $manager->read_text_file( File::Spec->catfile( $config_root, 'config.json' ) ) );
    my @telegram_collectors = grep { ref($_) eq 'HASH' && $_->{name} =~ /\Atelegram-codex-/ } @{ $saved->{collectors} };
    is( scalar @telegram_collectors, 1, 'ensure_collector_config leaves only the current workspace collector after healing a stale cross-session entry' );
    is( $telegram_collectors[0]{name}, 'telegram-codex-mt5-ai', 'ensure_collector_config keeps the governed collector for the current workspace session' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => File::Spec->catdir( $home, 'mt5-ai' ),
        home => $home,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
            TELEGRAM_CODEX_START_CAPTURE    => 1,
            TELEGRAM_CODEX_START_ACTIVE     => 1,
            CODEX_REAL_BIN                  => '/opt/codex/bin/codex-real',
        },
    );
    my $plan = $manager->execute_start;
    is( $plan->{start_collector}, 0, 'execute_start suppresses collector restart side effects when the managed start guard is already active in this process tree' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $workspace = File::Spec->catdir( $home, 'mt5-ai' );
    make_path($workspace);
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
        env  => {
            TELEGRAM_BOT_TOKEN           => 'token-xyz',
            TELEGRAM_CODEX_START_CAPTURE => 1,
            TELEGRAM_CODEX_RUNTIME_DIR   => '~/.telegram-codex',
            CODEX_REAL_BIN               => '/opt/codex/bin/codex-real',
        },
    );
    my $plan = $manager->execute_start('--audit');
    my $audit_flag = File::Spec->catfile( $home, '.telegram-codex', $plan->{collector_session_id}, 'audit.enabled' );
    ok( -f $audit_flag, 'execute_start --audit persists the per-session audit flag for the collector-owned worker' );
    is( $manager->read_text_file($audit_flag), "1\n", 'execute_start --audit writes the enabled audit marker content' );
    is( $plan->{collector_session_id}, 'mt5-ai', 'execute_start --audit still captures the governed collector session id' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $workspace = File::Spec->catdir( $home, 'workspace-collector' );
    make_path($workspace);
    my @commands;
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
        command_runner => sub {
            my ( $command, $meta ) = @_;
            push @commands, [ @$command, $meta->{plan}{collector_cwd}, $meta->{plan}{codex_session_id} ];
            return { ok => 1 };
        },
    );
    my $plan = {
        collector_session_id => 'workspace-collector',
        collector_name       => 'telegram-codex-workspace-collector',
        collector_cwd        => $workspace,
        codex_session_id     => 'session-saved-99',
    };
    $manager->ensure_startup_collector($plan);
    $manager->restart_startup_collector($plan);
    is_deeply(
        $commands[0],
        [ 'dashboard', 'restart', 'collector', 'telegram-codex-workspace-collector', $workspace, 'session-saved-99' ],
        'startup collector orchestration restarts the named DD collector after persisting the workspace session state',
    );
    is(
        $manager->read_codex_target_session_id(
            File::Spec->catfile( $home, '.telegram-codex', 'workspace-collector', 'codex.session' ),
        ),
        'session-saved-99',
        'ensure_startup_collector persists the Codex target session used for future Telegram replies',
    );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $workspace = File::Spec->catdir( $home, 'workspace-restart-system' );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($workspace);
    make_path($bin_dir);
    my $dashboard = File::Spec->catfile( $bin_dir, 'dashboard' );
    my $log = File::Spec->catfile( $home, 'dashboard-restart.log' );
    _write( $dashboard, "#!/bin/sh\nprintf '%s\\n' \"\$@\" > \"$log\"\nexit 0\n" );
    chmod 0755, $dashboard or die "Unable to chmod fake dashboard restart helper: $!";
    local $ENV{PATH} = $bin_dir;
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
    );
    my $result = $manager->restart_startup_collector(
        {
            collector_name => 'telegram-codex-workspace-restart-system',
        }
    );
    is( $result->{exit_code}, 0, 'restart_startup_collector succeeds through the real system command path' );
    my $restart_log = do {
        open my $fh, '<', $log or die $!;
        local $/;
        <$fh>;
    };
    is( $restart_log, "restart\ncollector\ntelegram-codex-workspace-restart-system\n", 'restart_startup_collector runs dashboard restart collector for the named session collector' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $runtime, 'session-overlap' );
    make_path($session_dir);
    _write( File::Spec->catfile( $session_dir, 'listener.pid' ), "424242\n" );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        pid_check_runner => sub {
            my ($pid) = @_;
            return $pid == 424242 ? 1 : 0;
        },
    );
    my $result = $manager->execute_check_messages( 'session-overlap', 1, 0 );
    is( $result->{skipped}, 1, 'execute_check_messages skips a second process when the same session suffix is already running' );
    is( $result->{running_pid}, 424242, 'execute_check_messages reports the existing running pid for the same session suffix' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
    );
    my $paths = $manager->listener_paths_for_session('session-stale-no-runner');
    $manager->write_text_file( $paths->{pid_file}, "999999\n" );
    my $guard = $manager->begin_check_message_session( 'session-stale-no-runner', $paths );
    is( $guard->{already_running}, 0, 'begin_check_message_session clears a stale pid file when the real process is gone' );
    is( $manager->read_text_file( $paths->{pid_file} ), "$$\n", 'begin_check_message_session replaces the stale pid file with the current worker pid' );
}

{
    my $manager = new_manager;
    ok( $manager->pid_is_running($$), 'pid_is_running uses the real kill-0 fallback when no test runner override is supplied' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $workspace = File::Spec->catdir( $home, 'workspace-start-live' );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($workspace);
    make_path($bin_dir);
    my $args_file = File::Spec->catfile( $home, 'collector-start.args' );
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex-real' );
    _write( $real_codex, "#!/bin/sh\nprintf '%s\\n' \"\$CODEX_SESSION_ID\" \"\$TELEGRAM_CODEX_SESSION_ID\" \"\$@\" > \"$args_file\"\nexit 0\n" );
    chmod 0755, $real_codex or die "Unable to chmod fake real codex for collector start test: $!";
    my $command_log = File::Spec->catfile( $home, 'collector-restart.log' );
    my $pid = fork();
    die "Unable to fork execute_start collector branch test: $!" if !defined $pid;
    if ( !$pid ) {
        my $manager = new_manager(
            cwd  => $workspace,
            home => $home,
            env  => {
                TELEGRAM_BOT_TOKEN              => 'token-xyz',
                TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
                CODEX_REAL_BIN                  => $real_codex,
            },
            command_runner => sub {
                my ($command) = @_;
                _write( $command_log, join( "\n", @$command ) . "\n" );
                return { ok => 1 };
            },
        );
        $manager->execute_start('--search');
        exit 95;
    }
    waitpid $pid, 0;
    is( $? >> 8, 0, 'execute_start runs the collector setup branch before launching the real codex binary' );
    my $restart_log = do {
        open my $fh, '<', $command_log or die $!;
        local $/;
        <$fh>;
    };
    is( $restart_log, "dashboard\nrestart\ncollector\ntelegram-codex-workspace-start-live\n", 'execute_start restarts the expected DD collector for the workspace session' );
    my $args = do {
        open my $fh, '<', $args_file or die $!;
        local $/;
        <$fh>;
    };
    is( $args, "workspace-start-live\nworkspace-start-live\n--search\n", 'execute_start exports the workspace session id into the launched Codex process' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $workspace = File::Spec->catdir( $home, 'skills' );
    make_path($workspace);
    my @signals;
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
        env  => {
            TELEGRAM_CODEX_RUNTIME_DIR => $home,
        },
        pid_check_runner => sub { return $_[0] == 424242 ? 1 : 0 },
        process_signal_runner => sub {
            my ( $signal, $pid ) = @_;
            push @signals, [ $signal, $pid ];
            return 1;
        },
        sleep_runner => sub { return 1; },
    );
    my $paths = $manager->listener_paths_for_session('skills');
    make_path( $paths->{runtime_dir} );
    _write( $paths->{pid_file}, "424242\n" );
    ok( $manager->recycle_check_message_session('skills'), 'recycle_check_message_session returns true when it finds and recycles an active per-session worker pid' );
    is_deeply( \@signals, [ [ 'TERM', 424242 ], [ 'KILL', 424242 ] ], 'recycle_check_message_session escalates from TERM to KILL when the worker still appears running' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $workspace = File::Spec->catdir( $home, 'skills' );
    make_path($workspace);
    my $manager = new_manager(
        cwd  => $workspace,
        home => $home,
        env  => {
            TELEGRAM_CODEX_RUNTIME_DIR => $home,
        },
        pid_check_runner => sub { return 0 },
    );
    my $paths = $manager->listener_paths_for_session('skills');
    make_path( $paths->{runtime_dir} );
    _write( $paths->{pid_file}, "424242\n" );
    ok( !$manager->recycle_check_message_session('skills'), 'recycle_check_message_session returns false when it only clears a stale dead pid file' );
    ok( !-f $paths->{pid_file}, 'recycle_check_message_session removes the stale pid file when the recorded worker is already gone' );
}

{
    my $manager = new_manager;
    ok( $manager->signal_process( 0, $$ ), 'signal_process falls back to the real kill path when no test runner override is supplied' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $workspace = File::Spec->catdir( $home, 'skills' );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($workspace);
    make_path($bin_dir);
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex-real' );
    my $args_file = File::Spec->catfile( $home, 'collector-recycle.args' );
    my $restart_log = File::Spec->catfile( $home, 'collector-recycle.restart' );
    my $recycle_log = File::Spec->catfile( $home, 'collector-recycle.called' );
    _write( $real_codex, "#!/bin/sh\nprintf '%s\\n' \"\$@\" > \"$args_file\"\nexit 0\n" );
    chmod 0755, $real_codex or die "Unable to chmod fake real codex for recycle test: $!";
    my $pid = fork();
    die "Unable to fork execute_start recycle branch test: $!" if !defined $pid;
    if ( !$pid ) {
        my $manager = new_manager(
            cwd  => $workspace,
            home => $home,
            env  => {
                TELEGRAM_BOT_TOKEN              => 'token-xyz',
                TELEGRAM_CODEX_ENABLE_AUTOSTART => '1',
                CODEX_REAL_BIN                  => $real_codex,
            },
            command_runner => sub {
                my ($command) = @_;
                _write( $restart_log, join( "\n", @{$command} ) . "\n" );
                return { ok => 1 };
            },
        );
        no warnings 'redefine';
        local *Telegram::Codex::Manager::recycle_check_message_session = sub {
            my ( $self, $session_id ) = @_;
            _write( $recycle_log, "$session_id\n" );
            return 1;
        };
        $manager->execute_start('--search');
        exit 0;
    }
    waitpid $pid, 0;
    is( $? >> 8, 0, 'execute_start succeeds after recycling an existing per-session check-message worker' );
    is( do { open my $fh, '<', $recycle_log or die $!; local $/; <$fh> }, "skills\n", 'execute_start invokes per-session worker recycling before restarting the collector' );
    is( do { open my $fh, '<', $restart_log or die $!; local $/; <$fh> }, "dashboard\nrestart\ncollector\ntelegram-codex-skills\n", 'execute_start still restarts the governed DD collector after recycling the old worker' );
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
            my ( $session_id, $paths, $options ) = @_;
            open my $fh, '>>', $listener_marker or die $!;
            print {$fh} "$session_id|$paths->{log_file}|$options->{mode}|$options->{codex_session_id}\n";
            close $fh or die $!;
        },
    );
    my $paths = $manager->start_listener_if_needed(
        'session-launch-88',
        mode             => 'codex-session',
        codex_session_id => 'session-launch-88',
    );
    ok( -f $paths->{pid_file}, 'start_listener_if_needed writes a pid file in the session runtime directory' );
    ok( defined $paths->{log_file} && $paths->{log_file} ne q{}, 'start_listener_if_needed returns the session log path' );
    is( $manager->read_text_file( $paths->{pid_file} ), "424242\n", 'start_listener_if_needed records the provided listener pid in test mode without forking a real listener' );
    my $marker = do {
        open my $fh, '<', $listener_marker or die $!;
        local $/;
        <$fh>;
    };
    like( $marker, qr/session-launch-88/, 'start_listener_if_needed runs the child listener startup path for the requested session' );
    like( $marker, qr/codex-session/, 'start_listener_if_needed passes the managed startup listener mode into the launch path' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $skill_root = File::Spec->catdir( $home, 'skill-root' );
    my $cli_dir = File::Spec->catdir( $skill_root, 'cli' );
    make_path($cli_dir);
    my $listen = File::Spec->catfile( $cli_dir, 'check-message' );
    _write( $listen, "#!/usr/bin/env perl\nsleep 30;\n" );
    chmod 0755, $listen or die "Unable to chmod fake running listener: $!";
    my $manager = new_manager(
        cwd        => $home,
        home       => $home,
        skill_root => $skill_root,
        env        => {
            TELEGRAM_CODEX_RUNTIME_DIR => $home,
        },
    );
    my $first = $manager->start_listener_if_needed('session-running-11');
    my $paths = $manager->start_listener_if_needed('session-running-11');
    is( $paths->{listener_running}, 1, 'start_listener_if_needed leaves an already-running session listener alone' );
    is( $paths->{pid}, $first->{pid}, 'start_listener_if_needed reports the existing running session listener pid' );
    kill 'TERM', $first->{pid};
    waitpid $first->{pid}, 0;
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
    my $skill_root = File::Spec->catdir( $home, 'skill-root' );
    my $cli_dir = File::Spec->catdir( $skill_root, 'cli' );
    make_path($cli_dir);
    my $listener_log = File::Spec->catfile( $home, 'listener.exec.log' );
    my $listen = File::Spec->catfile( $cli_dir, 'check-message' );
    _write( $listen, "#!/bin/sh\nprintf '%s\\n' \"\$TELEGRAM_CODEX_LISTENER_MODE\" \"\$TELEGRAM_CODEX_TARGET_SESSION_ID\" \"\$0\" \"\$@\" > \"$listener_log\"\n" );
    chmod 0755, $listen or die "Unable to chmod fake check-message command: $!";
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        skill_root => $skill_root,
        env  => {
            TELEGRAM_CODEX_RUNTIME_DIR => $home,
        },
    );
    my $paths = $manager->start_listener_if_needed(
        'session-forked-22',
        mode             => 'codex-session',
        codex_session_id => 'session-forked-22',
        reply_text       => 'listener ack',
    );
    waitpid $paths->{pid}, 0 if $paths->{pid};
    for ( 1 .. 20 ) {
        last if -f $listener_log;
        select undef, undef, undef, 0.05;
    }
    my $exec_log = do {
        open my $fh, '<', $listener_log or die $!;
        local $/;
        <$fh>;
    };
    is( $exec_log, "codex-session\nsession-forked-22\n$listen\n0\n30\nlistener ack\n", 'start_listener_if_needed can fork and exec the skill-owned check-message command directly with managed session-response env' );
    is( $manager->listener_command_path, $listen, 'listener_command_path resolves the skill-owned check-message command' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $skill_root = File::Spec->catdir( $home, 'skill-root' );
    my $cli_dir = File::Spec->catdir( $skill_root, 'cli' );
    make_path($cli_dir);
    my $listen = File::Spec->catfile( $cli_dir, 'check-message' );
    _write( $listen, "#!/usr/bin/env perl\nsleep 30;\n" );
    chmod 0755, $listen or die "Unable to chmod sleeping fake check-message command: $!";
    my $manager = new_manager(
        cwd        => $home,
        home       => $home,
        skill_root => $skill_root,
        env        => {
            TELEGRAM_CODEX_RUNTIME_DIR => $home,
        },
    );
    my $first = $manager->start_listener_if_needed('session-singleton-22');
    ok( $first->{pid}, 'start_listener_if_needed returns a real listener pid for the first launch' );
    my $second = $manager->start_listener_if_needed('session-singleton-22');
    is( $second->{listener_running}, 1, 'start_listener_if_needed reuses the existing listener for the same session' );
    is( $second->{pid}, $first->{pid}, 'start_listener_if_needed returns the same resident listener pid for the same session' );
    kill 'TERM', $first->{pid};
    waitpid $first->{pid}, 0;
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
    my $args_file = File::Spec->catfile( $home, 'ambient-ollama-ignored.args' );
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex-real' );
    _write( $real_codex, "#!/bin/sh\nprintf '%s\\n' \"\$@\" > \"$args_file\"\nexit 0\n" );
    chmod 0755, $real_codex or die "Unable to chmod fake real codex: $!";
    my $pid = fork();
    die "Unable to fork execute_start ambient ollama test: $!" if !defined $pid;
    if ( !$pid ) {
        my $manager = new_manager(
            cwd  => $home,
            home => $home,
            env  => {
                OLLAMA_MODEL  => '2',
                CODEX_REAL_BIN => $real_codex,
            },
        );
        $manager->execute_start('--search');
        exit 92;
    }
    waitpid $pid, 0;
    is( $? >> 8, 0, 'execute_start ignores ambient OLLAMA_MODEL and still execs the real codex binary' );
    my $args = do {
        open my $fh, '<', $args_file or die $!;
        local $/;
        <$fh>;
    };
    is( $args, "--search\n", 'execute_start does not route through Ollama just because the workspace exports OLLAMA_MODEL' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($bin_dir);
    my $args_file = File::Spec->catfile( $home, 'explicit-ollama.args' );
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex-real' );
    _write( $real_codex, "#!/bin/sh\nprintf '%s\\n' \"\$@\" > \"$args_file\"\nexit 0\n" );
    chmod 0755, $real_codex or die "Unable to chmod fake real codex: $!";
    my $pid = fork();
    die "Unable to fork execute_start explicit ollama test: $!" if !defined $pid;
    if ( !$pid ) {
        my $manager = new_manager(
            cwd  => $home,
            home => $home,
            env  => {
                TELEGRAM_CODEX_OLLAMA_MODEL => '1',
                CODEX_REAL_BIN              => $real_codex,
            },
        );
        $manager->execute_start('resume', 'session-x');
        exit 93;
    }
    waitpid $pid, 0;
    is( $? >> 8, 0, 'execute_start supports the explicit Telegram-owned Ollama model branch' );
    my $args = do {
        open my $fh, '<', $args_file or die $!;
        local $/;
        <$fh>;
    };
    is( $args, "--profile\nollama-launch\n-m\nqwen3.5:397b-cloud\nresume\nsession-x\n", 'execute_start injects the explicit Ollama Codex profile args directly into the real Codex exec path' );
}

{
    my $manager = new_manager(
        env => {
            TELEGRAM_CODEX_OLLAMA_MODEL => 'llama3.3:70b',
        },
    );
    is( $manager->explicit_start_ollama_model, 'llama3.3:70b', 'explicit_start_ollama_model preserves an explicitly requested Telegram-owned Ollama model name' );
    is_deeply(
        [ $manager->inject_ollama_codex_args( 'llama3.3:70b', '--profile', 'ollama-launch', '-m', 'llama3.3:70b', 'resume', 'session-x' ) ],
        [ '--profile', 'ollama-launch', '-m', 'llama3.3:70b', 'resume', 'session-x' ],
        'inject_ollama_codex_args does not prepend another Ollama profile when the argv already targets the Ollama launch profile',
    );
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
    my @post_calls;
    my @resume_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR      => $runtime,
            CODEX_SESSION_ID                => 'session-managed-listen',
            TELEGRAM_CODEX_LISTENER_MODE    => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-managed-listen',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 40,
                        message   => {
                            message_id => 12,
                            text       => 'hello2',
                            chat       => { id => 88, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary ) = @_;
            push @resume_calls, [ $session_id, $prompt, $summary ];
            return 'This is a real Codex session reply.';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 601, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $result = $manager->execute_listen( 1, 0 );
    is( $result->{processed}, 1, 'managed listener mode processes inbound Telegram messages' );
    is( $result->{replied}, 1, 'managed listener mode sends one reply after Codex generates it' );
    is( scalar @resume_calls, 1, 'managed listener mode resumes the active Codex session to generate the Telegram reply text' );
    is( $resume_calls[0][0], 'session-managed-listen', 'managed listener mode targets the active Codex session id' );
    like( $resume_calls[0][1], qr/text=hello2/, 'managed listener mode passes the inbound Telegram text into the Codex reply prompt' );
    is( $post_calls[0][0], 'sendChatAction', 'managed listener mode sends a typing action before the Codex-generated reply' );
    is( $post_calls[0][1]{action}, 'typing', 'managed listener mode uses Telegram typing status while the Codex reply is being generated' );
    like( $post_calls[1][1]{text}, qr/Codex verbose/, 'managed listener mode now opens the verbose trace before the final reply' );
    is( $post_calls[-2][1]{text}, 'This is a real Codex session reply.', 'managed listener mode sends the Codex-generated reply instead of a placeholder' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my @resume_calls;
    my @typing_events;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        typing_guard_runner => sub {
            my ( $summary, $self ) = @_;
            push @typing_events, 'guard-start';
            return sub {
                push @typing_events, 'guard-stop';
                return 1;
            };
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 101,
                        message   => {
                            message_id => 19,
                            text       => 'Hi',
                            chat       => { id => 99, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary ) = @_;
            push @typing_events, 'resume';
            push @resume_calls, [ $session_id, $prompt, $summary ];
            return 'Collector reply from Codex session.';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            push @typing_events, 'send' if $method ne 'sendChatAction';
            return {
                ok     => JSON::XS::true,
                result => { message_id => 777, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_codex_target_session_id( 'skills', 'session-from-ledger' );
    my $result = $manager->execute_check_messages( 'skills', 1, 0 );
    is( $result->{session_id}, 'skills', 'collector-owned check-message keeps the explicit session suffix' );
    is( $result->{processed}, 1, 'collector-owned check-message processes inbound messages for the explicit session' );
    is( $result->{replied}, 1, 'collector-owned check-message auto-replies through the persisted Codex session target' );
    is( scalar @resume_calls, 1, 'collector-owned check-message resumes Codex exactly once' );
    is( $resume_calls[0][0], 'session-from-ledger', 'collector-owned check-message uses the persisted codex.session target for replies' );
    like( $resume_calls[0][1], qr/text=Hi/, 'collector-owned check-message passes the inbound text into the Codex reply prompt' );
    is( $post_calls[0][0], 'sendChatAction', 'collector-owned check-message sends a typing action before the reply in managed Codex-session mode' );
    is( $post_calls[0][1]{action}, 'typing', 'collector-owned check-message uses Telegram typing status while Codex is generating the reply' );
    is( $post_calls[-2][0], 'sendMessage', 'collector-owned check-message sends the final Telegram reply after the typing action and verbose trace' );
    is( $post_calls[-2][1]{text}, 'Collector reply from Codex session.', 'collector-owned check-message sends the Codex-generated reply text' );
    is( $typing_events[0], 'guard-start', 'collector-owned check-message starts the typing guard before managed reply work' );
    is( $typing_events[1], 'send', 'collector-owned check-message emits the initial verbose trace while the typing guard is active' );
    is( $typing_events[2], 'resume', 'collector-owned check-message resumes Codex while the typing guard is active' );
    ok( scalar( grep { $_ eq 'send' } @typing_events ) >= 1, 'collector-owned check-message performs Telegram sends while the typing guard remains active' );
    is( $typing_events[-1], 'guard-stop', 'collector-owned check-message stops the typing guard after Telegram delivery work finishes' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my @resume_calls;
    my @typing_events;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 301,
                        message   => {
                            message_id => 44,
                            text       => 'These make it better',
                            chat       => { id => 66, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary, $opts ) = @_;
            push @resume_calls, [ $session_id, $prompt, $summary ];
            push @typing_events, 'resume';
            $opts->{on_progress}->('Turn started') if $opts && $opts->{on_progress};
            $opts->{on_progress}->('Agent: Planning the next step') if $opts && $opts->{on_progress};
            $opts->{on_progress}->('Running command: /bin/bash -lc pwd') if $opts && $opts->{on_progress};
            $opts->{on_progress}->('Command finished (exit 0): /bin/bash -lc pwd') if $opts && $opts->{on_progress};
            return 'Done. Final task result.';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            push @typing_events, 'send' if $method eq 'sendMessage' && ( $params->{text} || q{} ) eq 'Done. Final task result.';
            return {
                ok     => JSON::XS::true,
                result => {
                    message_id => ( $method eq 'sendMessage' ? 900 : 901 ),
                    chat       => { id => $params->{chat_id} },
                    text       => $params->{text},
                },
            };
        },
        typing_guard_runner => sub {
            my ( $summary, $self ) = @_;
            push @typing_events, 'typing-start';
            return sub {
                push @typing_events, 'typing-stop';
                return 1;
            };
        },
    );
    $manager->write_codex_target_session_id( 'skills', 'session-from-ledger' );
    my $result = $manager->execute_check_messages( 'skills', 1, 0 );
    my @texts = map { $_->[1]{text} } grep { $_->[1]{text} } @post_calls;
    is( $result->{processed}, 1, 'collector-owned check-message processes the inbound Telegram message' );
    is( $result->{replied}, 1, 'collector-owned check-message still sends the final Telegram reply' );
    is_deeply( \@typing_events, [ 'typing-start', 'resume', 'send', 'typing-stop' ], 'collector-owned check-message keeps typing around the managed Codex work through final delivery' );
    is( scalar @resume_calls, 1, 'collector-owned check-message resumes Codex once when the first reply is substantive' );
    is( $post_calls[1][0], 'sendMessage', 'collector-owned check-message sends a verbose progress message before the final reply even for conversational follow-up text' );
    like( $post_calls[1][1]{text}, qr/Codex verbose/, 'collector-owned check-message opens the progress stream with a verbose trace message' );
    like( $post_calls[1][1]{text}, qr/Resuming active Codex session/, 'collector-owned check-message emits an immediate verbose kickoff line before richer Codex events arrive' );
    ok( scalar( grep { $_->[0] eq 'editMessageText' } @post_calls ) >= 1, 'collector-owned check-message updates the verbose trace in place' );
    like( join( "\n---\n", @texts ), qr/Agent: Planning the next step/, 'collector-owned check-message streams real agent events into Telegram' );
    like( join( "\n---\n", @texts ), qr/Running command: \/bin\/bash -lc pwd/, 'collector-owned check-message streams real command-start events into Telegram' );
    like( join( "\n---\n", @texts ), qr/Final reply sent/, 'collector-owned check-message records final delivery in the verbose trace' );
    is( $post_calls[-2][1]{text}, 'Done. Final task result.', 'collector-owned check-message still sends the final substantive Telegram reply' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my @resume_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 0,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-session',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 9001,
                        message   => {
                            message_id => 301,
                            text       => 'Hi from unpaired chat',
                            chat       => { id => 707, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            push @resume_calls, [@_];
            return 'unexpected';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 901, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->set_listener_audit_enabled( 'pairing-session', 1 );
    my $result = $manager->execute_check_messages( 'pairing-session', 1, 0 );
    my $state = $manager->read_listener_pairing_state( $manager->listener_paths_for_session('pairing-session') );
    my $audit = $manager->read_text_file( $manager->listener_paths_for_session('pairing-session')->{audit_file} );
    is( $result->{processed}, 1, 'pairing gate still records the unpaired inbound message' );
    is( $result->{replied}, 1, 'pairing gate sends one pairing command reply for the first unpaired message' );
    is( scalar @resume_calls, 0, 'pairing gate does not resume Codex before the session is paired' );
    is( $post_calls[0][0], 'sendMessage', 'pairing gate sends the pairing command through a normal Telegram reply' );
    like( $post_calls[0][1]{text}, qr/\Ad2 telegram-codex\.pair [0-9a-f]{16}\z/, 'pairing gate replies with the local pairing command and a random hex code' );
    is( $state->{pending_chat_id}, 707, 'pairing gate records the pending chat id for the first unpaired user' );
    is( $state->{pairing_code}, ( split / /, $post_calls[0][1]{text} )[-1], 'pairing gate persists the same challenge code it returned to Telegram' );
    like( $audit, qr/"type"\s*:\s*"pairing\.challenge\.sent"/, 'pairing gate records the challenge send decision in the session audit' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 0,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-session',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 9002,
                        message   => {
                            message_id => 302,
                            text       => 'Still talking before pairing',
                            chat       => { id => 707, type => 'private' },
                        },
                    },
                ],
            };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 902, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_listener_pairing_state(
        $manager->listener_paths_for_session('pairing-session'),
        {
            pending_chat_id => 707,
            pairing_code    => 'deadbeefcafebabe',
        },
    );
    my $result = $manager->execute_check_messages( 'pairing-session', 1, 0 );
    is( $result->{processed}, 1, 'pairing gate still records repeated unpaired messages' );
    is( $result->{replied}, 0, 'pairing gate ignores repeated messages from the pending unpaired chat until the local pair command runs' );
    is( scalar @post_calls, 0, 'pairing gate sends no second challenge reply before pairing is completed locally' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my @resume_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 0,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-session',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 90021,
                        message   => {
                            message_id => 3021,
                            text       => 'Second unpaired chat should be ignored',
                            chat       => { id => 808, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            push @resume_calls, [@_];
            return 'unexpected';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 9021, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_listener_pairing_state(
        $manager->listener_paths_for_session('pairing-session'),
        {
            pending_chat_id => 707,
            pairing_code    => 'deadbeefcafebabe',
        },
    );
    my $result = $manager->execute_check_messages( 'pairing-session', 1, 0 );
    is( $result->{processed}, 1, 'pairing gate still records outsider messages while another chat has the pending challenge' );
    is( $result->{replied}, 0, 'pairing gate ignores a different unpaired chat while the pending challenge belongs to someone else' );
    is( scalar @resume_calls, 0, 'pairing gate does not resume Codex for a different unpaired chat while pairing is pending elsewhere' );
    is( scalar @post_calls, 0, 'pairing gate does not send a second challenge to a different unpaired chat while one is already pending' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my @resume_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 0,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-session',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 90022,
                        message   => {
                            message_id => 3022,
                            text       => 'First pairing challenge send should fail cleanly',
                            chat       => { id => 909, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            push @resume_calls, [@_];
            return 'unexpected';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            die "Telegram POST failed for sendMessage: 500 Pairing challenge send failure\n" if $method eq 'sendMessage';
            return {
                ok     => JSON::XS::true,
                result => { message_id => 9022, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $result = $manager->execute_check_messages( 'pairing-session', 1, 0 );
    my $state = $manager->read_listener_pairing_state( $manager->listener_paths_for_session('pairing-session') );
    is( $result->{processed}, 1, 'pairing gate still records the first unpaired message when the challenge reply send fails' );
    is( $result->{replied}, 0, 'pairing gate does not count a failed challenge reply as replied' );
    is( scalar @resume_calls, 0, 'pairing gate still does not resume Codex when the challenge reply send fails' );
    like( $result->{reply_errors}[0]{error}, qr/Pairing challenge send failure/, 'pairing gate records the challenge reply send failure' );
    is( $state->{pending_chat_id}, 909, 'pairing gate still persists the pending chat after a failed challenge reply send' );
    is( scalar @post_calls, 1, 'pairing gate attempts the challenge reply once when the send fails' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 0,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-session',
        },
    );
    my $paths = $manager->listener_paths_for_session('pairing-session');
    $manager->write_listener_pairing_state(
        $paths,
        {
            pending_chat_id => 707,
            pairing_code    => 'deadbeefcafebabe',
        },
    );
    my $result = $manager->execute_pair('deadbeefcafebabe');
    my $state = $manager->read_listener_pairing_state($paths);
    is( $result->{paired_chat_id}, 707, 'execute_pair pairs the pending Telegram chat to the current session' );
    is( $state->{paired_chat_id}, 707, 'execute_pair persists the paired chat id' );
    ok( !exists $state->{pairing_code}, 'execute_pair clears the consumed challenge code' );
    ok( !exists $state->{pending_chat_id}, 'execute_pair clears the pending chat after successful pairing' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @resume_calls;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 0,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-session',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 9003,
                        message   => {
                            message_id => 303,
                            text       => 'Now do the work',
                            chat       => { id => 707, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            push @resume_calls, [@_];
            return 'Paired reply.';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 903, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_listener_pairing_state(
        $manager->listener_paths_for_session('pairing-session'),
        {
            paired_chat_id => 707,
            paired_at      => '2026-05-22 12:00:00',
        },
    );
    $manager->write_codex_target_session_id( 'pairing-session', 'paired-session-target' );
    my $result = $manager->execute_check_messages( 'pairing-session', 1, 0 );
    is( $result->{replied}, 1, 'paired chat resumes normal reply behavior after local pairing' );
    is( scalar @resume_calls, 1, 'paired chat is allowed through to the Codex session' );
    is( $post_calls[-2][1]{text}, 'Paired reply.', 'paired chat still receives the final Codex reply text' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @resume_calls;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 0,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-session',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 9004,
                        message   => {
                            message_id => 304,
                            text       => 'Different chat should be ignored',
                            chat       => { id => 808, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            push @resume_calls, [@_];
            return 'unexpected';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 904, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_listener_pairing_state(
        $manager->listener_paths_for_session('pairing-session'),
        {
            paired_chat_id => 707,
            paired_at      => '2026-05-22 12:00:00',
        },
    );
    my $result = $manager->execute_check_messages( 'pairing-session', 1, 0 );
    is( $result->{processed}, 1, 'paired-session security still records the ignored outsider message' );
    is( $result->{replied}, 0, 'paired-session security ignores messages from unpaired chats after pairing is complete' );
    is( scalar @resume_calls, 0, 'paired-session security does not resume Codex for outsider chats' );
    is( scalar @post_calls, 0, 'paired-session security does not reply to outsider chats' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 1,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-disabled-session',
        },
    );
    my $paths = $manager->listener_paths_for_session('pairing-disabled-session');
    $manager->set_listener_audit_enabled( 'pairing-disabled-session', 1 );
    my $result = $manager->listener_pairing_action(
        {
            chat       => { id => 919 },
            update_id  => 99001,
            message_id => 9901,
            text       => 'pairing bypassed',
        },
        $paths,
    );
    my $audit = $manager->read_text_file( $paths->{audit_file} );
    is( $result->{allow}, 1, 'listener_pairing_action allows the chat when pairing is explicitly disabled' );
    like( $audit, qr/"type"\s*:\s*"pairing\.allowed"/, 'listener_pairing_action records pairing.allowed in the audit when pairing is explicitly disabled' );
    like( $audit, qr/"reason"\s*:\s*"disabled"/, 'listener_pairing_action records the disabled reason in the audit when pairing is bypassed' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_DISABLE_PAIRING => 0,
            TELEGRAM_BOT_TOKEN             => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR     => $runtime,
            CODEX_SESSION_ID               => 'pairing-missing-chat-session',
        },
    );
    my $paths = $manager->listener_paths_for_session('pairing-missing-chat-session');
    $manager->set_listener_audit_enabled( 'pairing-missing-chat-session', 1 );
    my $result = $manager->listener_pairing_action(
        {
            chat       => {},
            update_id  => 99002,
            message_id => 9902,
            text       => 'no chat id',
        },
        $paths,
    );
    my $audit = $manager->read_text_file( $paths->{audit_file} );
    is( $result->{allow}, 1, 'listener_pairing_action allows updates with no chat id' );
    like( $audit, qr/"type"\s*:\s*"pairing\.allowed"/, 'listener_pairing_action records pairing.allowed in the audit when chat id is missing' );
    like( $audit, qr/"reason"\s*:\s*"missing-chat-id"/, 'listener_pairing_action records the missing-chat-id reason in the audit' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my @resume_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 10101,
                        message   => {
                            message_id => 193,
                            text       => 'Static collector reply',
                            chat       => { id => 98, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            push @resume_calls, [@_];
            return 'unexpected';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 782, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $result = $manager->execute_check_messages( 'skills', 1, 0, 'Static collector reply sent.' );
    is( $result->{processed}, 1, 'collector-owned check-message processes inbound messages in static reply mode too' );
    is( $result->{replied}, 1, 'collector-owned check-message sends a static reply when explicit reply text is supplied' );
    is( scalar @resume_calls, 0, 'collector-owned check-message does not resume Codex in static reply mode' );
    is( scalar @post_calls, 1, 'collector-owned check-message sends only the final Telegram reply in static reply mode' );
    is( $post_calls[0][0], 'sendMessage', 'collector-owned check-message does not send typing status in static reply mode' );
    is( $post_calls[0][1]{text}, 'Static collector reply sent.', 'collector-owned check-message sends the explicit static reply text' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @typing_events;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        typing_guard_runner => sub {
            my ( $summary, $self ) = @_;
            push @typing_events, 'guard-start';
            return sub {
                push @typing_events, 'guard-stop';
                return 1;
            };
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 1011,
                        message   => {
                            message_id => 191,
                            text       => 'Guard cleanup on failure',
                            chat       => { id => 99, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            push @typing_events, 'resume';
            die "Codex resume failed for Telegram reply\n";
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 780, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_codex_target_session_id( 'skills', 'session-from-ledger' );
    my $result = $manager->execute_check_messages( 'skills', 1, 0 );
    is( $result->{processed}, 1, 'collector-owned check-message still records the inbound message when managed Codex reply generation fails' );
    is( $result->{replied}, 0, 'collector-owned check-message does not count a failed managed Codex reply generation as replied' );
    like( $result->{reply_errors}[0]{error}, qr/Codex resume failed for Telegram reply/, 'collector-owned check-message records the managed Codex failure' );
    is_deeply( \@typing_events, [ 'guard-start', 'resume', 'guard-stop' ], 'typing guard cleanup still runs when the managed Codex reply generation fails' );
    is( scalar @post_calls, 2, 'collector-owned check-message sends typing plus the initial verbose trace before the managed reply failure' );
    is( $post_calls[0][0], 'sendChatAction', 'collector-owned check-message sends typing before the managed reply failure' );
    like( $post_calls[1][1]{text}, qr/Codex verbose/, 'collector-owned check-message sends the initial verbose trace before the managed reply failure' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @typing_events;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        typing_guard_runner => sub {
            my ( $summary, $self ) = @_;
            push @typing_events, 'guard-start';
            return sub {
                push @typing_events, 'guard-stop';
                return 1;
            };
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 1012,
                        message   => {
                            message_id => 192,
                            text       => 'Guard cleanup on send failure',
                            chat       => { id => 99, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            push @typing_events, 'resume';
            return 'Reply before send failure.';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @typing_events, 'send' if $method eq 'sendMessage';
            die "Telegram POST failed for sendMessage: 500 Internal Server Error\n" if $method eq 'sendMessage';
            return {
                ok     => JSON::XS::true,
                result => { message_id => 781, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_codex_target_session_id( 'skills', 'session-from-ledger' );
    my $result = $manager->execute_check_messages( 'skills', 1, 0 );
    is( $result->{processed}, 1, 'collector-owned check-message still records the inbound message when final Telegram delivery fails' );
    is( $result->{replied}, 0, 'collector-owned check-message does not count a failed final Telegram delivery as replied' );
    like( $result->{reply_errors}[0]{error}, qr/sendMessage: 500 Internal Server Error/, 'collector-owned check-message records the final Telegram delivery failure' );
    is_deeply( \@typing_events, [ 'guard-start', 'send', 'resume', 'send', 'guard-stop' ], 'typing guard cleanup still runs after a final Telegram delivery failure even with the initial verbose trace send' );
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
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { ok => JSON::XS::true },
            };
        },
    );
    my @typing_errors;
    my $returned = $manager->with_listener_typing_status(
        {
            update_id => 2001,
            message_id => 91,
            chat => { id => 99, type => 'private' },
            text => 'void context branch',
        },
        typing_errors => \@typing_errors,
        code => sub {
            push @typing_errors, { marker => 'callback-ran' };
            return 'unused';
        },
    );
    is( $returned, 'unused', 'with_listener_typing_status returns callback result in scalar context' );
    is( $post_calls[0][0], 'sendChatAction', 'with_listener_typing_status sends the initial typing action directly' );
    is( $typing_errors[-1]{marker}, 'callback-ran', 'with_listener_typing_status runs the callback body' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            die "Telegram POST failed for sendChatAction: 429 Too Many Requests\n" if $method eq 'sendChatAction';
            return { ok => JSON::XS::true, result => { ok => JSON::XS::true } };
        },
    );
    my $error = $manager->send_telegram_typing_action_for_chat(88);
    is( $error->{chat_id}, 88, 'send_telegram_typing_action_for_chat returns the chat id when Telegram typing fails directly' );
    like( $error->{error}, qr/sendChatAction: 429 Too Many Requests/, 'send_telegram_typing_action_for_chat returns the Telegram typing failure detail instead of dying' );
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
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { ok => JSON::XS::true },
            };
        },
    );
    my @values = $manager->with_listener_typing_status(
        {
            update_id => 20011,
            message_id => 911,
            chat => { id => 99, type => 'private' },
            text => 'list context branch',
        },
        code => sub {
            return ( 'first', 'second' );
        },
    );
    is_deeply( \@values, [ 'first', 'second' ], 'with_listener_typing_status returns callback results in list context' );
    is( $post_calls[0][0], 'sendChatAction', 'with_listener_typing_status still sends typing in list context' );
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
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { ok => JSON::XS::true },
            };
        },
    );
    my $ran = 0;
    $manager->with_listener_typing_status(
        {
            update_id => 20012,
            message_id => 912,
            chat => { id => 99, type => 'private' },
            text => 'void context branch',
        },
        code => sub {
            $ran = 1;
            return 'ignored';
        },
    );
    ok( $ran, 'with_listener_typing_status runs the callback body in void context' );
    is( $post_calls[0][0], 'sendChatAction', 'with_listener_typing_status still sends typing in void context' );
}

{
    my $manager = new_manager;
    is_deeply(
        [ $manager->codex_progress_lines_for_event( { type => 'thread.started' } ) ],
        ['Session resumed'],
        'codex_progress_lines_for_event formats thread.started'
    );
    is_deeply(
        [ $manager->codex_progress_lines_for_event( { type => 'turn.started' } ) ],
        ['Turn started'],
        'codex_progress_lines_for_event formats turn.started'
    );
    is_deeply(
        [ $manager->codex_progress_lines_for_event( { type => 'item.started', item => { type => 'command_execution', command => '/bin/bash -lc pwd' } } ) ],
        ['Running command: /bin/bash -lc pwd'],
        'codex_progress_lines_for_event formats command start events'
    );
    is_deeply(
        [ $manager->codex_progress_lines_for_event( { type => 'item.completed', item => { type => 'command_execution', command => '/bin/bash -lc pwd', exit_code => 0, aggregated_output => "/tmp\n" } } ) ],
        [ 'Command finished (exit 0): /bin/bash -lc pwd', 'Output: /tmp' ],
        'codex_progress_lines_for_event formats command completion events with output'
    );
    is_deeply(
        [ $manager->codex_progress_lines_for_event( { type => 'item.completed', item => { type => 'agent_message', text => "Planning\nDone" } } ) ],
        [ 'Agent: Planning', 'Agent: Done' ],
        'codex_progress_lines_for_event formats agent messages line by line'
    );
    is_deeply(
        [ $manager->codex_progress_lines_for_event( { type => 'item.completed', item => { type => 'unknown' } } ) ],
        [],
        'codex_progress_lines_for_event returns no lines for unrelated event payloads'
    );
}

{
    my $manager = new_manager;
    ok(
        $manager->listener_should_stream_progress( { text => 'These make it better', chat => { id => 1 }, message_id => 2 } ),
        'listener_should_stream_progress stays on for conversational managed Codex replies'
    );
    ok(
        $manager->telegram_message_requires_completion( { text => 'Run all the tests and check if any test not good enough' } ),
        'telegram_message_requires_completion recognizes run-and-check task requests as long-running work'
    );
    ok(
        $manager->telegram_message_requires_completion( { text => 'Review the current implementation and verify the release gate' } ),
        'telegram_message_requires_completion recognizes review-and-verify task requests as long-running work'
    );
    ok(
        !$manager->telegram_message_requires_completion( { text => 'What is the status?' } ),
        'telegram_message_requires_completion does not force verbose task streaming for simple status questions'
    );
}

{
    my $manager = new_manager;
    my @trimmed = $manager->listener_verbose_trimmed_lines( ('short line') x 11, ( 'x' x 3400 ) );
    ok( scalar(@trimmed) < 12, 'listener_verbose_trimmed_lines drops older lines until the rendered verbose message fits Telegram limits' );
    is( $trimmed[-1], 'x' x 3400, 'listener_verbose_trimmed_lines keeps the newest line while trimming oversized verbose output' );
    ok( length( $manager->listener_verbose_text(@trimmed) ) <= 3500, 'listener_verbose_trimmed_lines returns text that fits the Telegram edit budget' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR      => $runtime,
            TELEGRAM_CODEX_LISTENER_MODE    => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-task-work',
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 995, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $reporter = $manager->start_listener_verbose_reporter(
        {
            update_id  => 30020,
            message_id => 320,
            chat       => { id => 88, type => 'private' },
            text       => 'Finish all tasks with all gates',
        },
    );
    ok( $reporter, 'start_listener_verbose_reporter returns a reporter object for managed Codex-session updates' );
    ok( $reporter->{emit}->('Turn started'), 'start_listener_verbose_reporter can emit the first verbose line' );
    ok( $reporter->{emit}->('Running command: /bin/bash -lc pwd'), 'start_listener_verbose_reporter can append later verbose lines' );
    ok( $reporter->{finish}->(), 'start_listener_verbose_reporter exposes a finish callback' );
    is( $post_calls[0][0], 'sendMessage', 'start_listener_verbose_reporter sends the first verbose trace message' );
    like( $post_calls[0][1]{text}, qr/Codex verbose\n- Turn started/, 'start_listener_verbose_reporter renders the initial verbose trace text' );
    is( $post_calls[1][0], 'editMessageText', 'start_listener_verbose_reporter edits the same Telegram message for later lines' );
    like( $post_calls[1][1]{text}, qr/Running command: \/bin\/bash -lc pwd/, 'start_listener_verbose_reporter includes later streamed steps in the edited message' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @errors;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR      => $runtime,
            TELEGRAM_CODEX_LISTENER_MODE    => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-task-work',
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            die "Telegram POST failed for editMessageText: 500 Internal Server Error\n" if $method eq 'editMessageText';
            return {
                ok     => JSON::XS::true,
                result => { message_id => 996, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $reporter = $manager->start_listener_verbose_reporter(
        {
            update_id  => 30021,
            message_id => 321,
            chat       => { id => 88, type => 'private' },
            text       => 'Finish all tasks with all gates',
        },
        on_error => sub { push @errors, @_; return 1; },
    );
    ok( $reporter->{emit}->('Turn started'), 'start_listener_verbose_reporter still emits the first line when Telegram accepts the initial trace message' );
    ok( !$reporter->{emit}->('Running command: /bin/bash -lc pwd'), 'start_listener_verbose_reporter converts later edit failures into a false return instead of dying' );
    like( $errors[0], qr/editMessageText: 500 Internal Server Error/, 'start_listener_verbose_reporter reports the Telegram verbose edit failure through the error callback' );
    is( $post_calls[0][0], 'sendMessage', 'start_listener_verbose_reporter still posts the initial verbose trace message before the edit failure' );
    is( $post_calls[1][0], 'editMessageText', 'start_listener_verbose_reporter attempted the later in-place edit before reporting the failure' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @errors;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN               => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR       => $runtime,
            TELEGRAM_CODEX_LISTENER_MODE     => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-task-work',
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            die "Telegram POST failed for sendMessage: 500 Initial verbose trace rejected\n" if $method eq 'sendMessage';
            return {
                ok     => JSON::XS::true,
                result => { message_id => 997, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $reporter = $manager->start_listener_verbose_reporter(
        {
            update_id  => 30022,
            message_id => 322,
            chat       => { id => 88, type => 'private' },
            text       => 'Finish all tasks with all gates',
        },
        on_error => sub { push @errors, @_; return 1; },
    );
    ok( $reporter, 'start_listener_verbose_reporter still returns a reporter object when the first verbose send fails' );
    ok( !$reporter->{emit}->('Turn started'), 'start_listener_verbose_reporter returns false instead of dying when the first verbose send is rejected' );
    like( $errors[0], qr/sendMessage: 500 Initial verbose trace rejected/, 'start_listener_verbose_reporter reports the initial verbose send failure through the error callback' );
    is( $post_calls[0][0], 'sendMessage', 'start_listener_verbose_reporter attempted the initial verbose trace send before disabling itself' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
    );
    my $paths = $manager->listener_paths_for_session('audit-direct');
    ok( !$manager->listener_audit_enabled($paths), 'listener audit is disabled by default without env or marker file' );
    ok( $manager->set_listener_audit_enabled( 'audit-direct', 1 ), 'set_listener_audit_enabled writes the per-session audit marker file' );
    ok( $manager->listener_audit_enabled($paths), 'listener audit becomes enabled after the marker file is written' );
    ok(
        $manager->append_listener_audit_event(
            $paths,
            'audit.direct',
            {
                worked => JSON::XS::true,
                note   => 'written from direct test',
            },
        ),
        'append_listener_audit_event writes a JSONL audit row when audit is enabled',
    );
    my @rows = grep { defined $_ && $_ ne q{} } split /\n/, $manager->read_text_file( $paths->{audit_file} );
    my $decoded = decode_json( $rows[0] );
    is( $decoded->{type}, 'audit.direct', 'append_listener_audit_event persists the event type' );
    is( $decoded->{note}, 'written from direct test', 'append_listener_audit_event persists the supplied payload fields' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR      => $runtime,
            TELEGRAM_CODEX_LISTENER_MODE    => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-task-work',
        },
        fork_runner => sub { return undef; },
        post_runner => sub {
            my ( $method, $params ) = @_;
            return {
                ok     => JSON::XS::true,
                result => { message_id => 990, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $guard = $manager->start_listener_progress_guard(
        {
            update_id  => 30001,
            message_id => 301,
            chat       => { id => 88, type => 'private' },
            text       => 'Finish all tasks with all gates',
        },
    );
    ok( $guard, 'start_listener_progress_guard falls back to a cleanup callback when the progress fork cannot be created' );
    ok( $guard->(), 'progress cleanup callback from fork failure is still callable' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $progress_log = File::Spec->catfile( $runtime, 'progress.log' );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR      => $runtime,
            TELEGRAM_CODEX_LISTENER_MODE    => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-task-work',
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            open my $fh, '>>', $progress_log or die $!;
            print {$fh} "$method\n";
            close $fh or die $!;
            return {
                ok     => JSON::XS::true,
                result => { message_id => 991, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    my $summary = {
        update_id  => 30002,
        message_id => 302,
        chat       => { id => 88, type => 'private' },
        text       => 'Finish all tasks with all gates',
    };
    is(
        $manager->listener_progress_text( 'start', 0 ),
        'Codex is working on your request in this session. I will send the final result when the work is done.',
        'listener_progress_text returns the initial managed progress message'
    );
    is(
        $manager->listener_progress_text( 'continue', 1 ),
        'Codex is still working on your request...',
        'listener_progress_text returns the repeating managed progress message'
    );
    is( $manager->listener_progress_interval_seconds, 5, 'listener_progress_interval_seconds returns the default progress heartbeat interval' );
    local *Telegram::Codex::Manager::listener_progress_interval_seconds = sub { return 0.1; };
    my $guard = $manager->start_listener_progress_guard($summary);
    ok( $guard, 'start_listener_progress_guard returns a cleanup callback for the real forked progress path' );
    select undef, undef, undef, 0.25;
    $guard->();
    my $log = do {
        open my $fh, '<', $progress_log or die $!;
        local $/;
        <$fh>;
    };
    like( $log, qr/sendMessage/, 'start_listener_progress_guard posts the initial progress message' );
    like( $log, qr/editMessageText/, 'start_listener_progress_guard refreshes the progress message while work is still running' );
    like( $log, qr/deleteMessage/, 'start_listener_progress_guard deletes the progress message after cleanup' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
    );
    my $guard = $manager->start_listener_typing_guard(
        {
            update_id => 2002,
            message_id => 92,
            chat => { type => 'private' },
            text => q{},
        },
    );
    ok( !defined $guard, 'start_listener_typing_guard returns undef when the update does not qualify for managed typing status' );
    ok( !defined $manager->send_listener_typing_action( { chat => { id => 99 }, text => q{} } ), 'send_listener_typing_action is a no-op when the update does not qualify for typing status' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        fork_runner => sub { return undef; },
    );
    my $guard = $manager->start_listener_typing_guard(
        {
            update_id => 20021,
            message_id => 921,
            chat => { id => 99, type => 'private' },
            text => 'simulated fork failure',
        },
    );
    ok( !defined $guard, 'start_listener_typing_guard falls back cleanly when the heartbeat fork cannot be created' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $typing_log = File::Spec->catfile( $runtime, 'typing.log' );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            open my $fh, '>>', $typing_log or die $!;
            print {$fh} "$method\n";
            close $fh or die $!;
            return {
                ok     => JSON::XS::true,
                result => { ok => JSON::XS::true },
            };
        },
    );
    my $summary = {
        update_id => 2003,
        message_id => 93,
        chat => { id => 99, type => 'private' },
        text => 'forked typing guard branch',
    };
    local *Telegram::Codex::Manager::listener_typing_interval_seconds = sub { return 0.1; };
    my $guard = $manager->start_listener_typing_guard($summary);
    ok( $guard, 'start_listener_typing_guard returns a cleanup callback for the real forked heartbeat path' );
    select undef, undef, undef, 0.25;
    $guard->();
    my $log = do {
        open my $fh, '<', $typing_log or die $!;
        local $/;
        <$fh>;
    };
    like( $log, qr/sendChatAction/, 'start_listener_typing_guard sends repeated typing actions from the forked heartbeat path' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my @resume_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 102,
                        message   => {
                            message_id => 20,
                            text       => 'Typing failure should not block reply',
                            chat       => { id => 99, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary ) = @_;
            push @resume_calls, [ $session_id, $prompt, $summary ];
            return 'Reply still sent after typing failure.';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            die "Telegram POST failed for sendChatAction: 429 Too Many Requests\n" if $method eq 'sendChatAction';
            return {
                ok     => JSON::XS::true,
                result => { message_id => 778, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_codex_target_session_id( 'skills', 'session-from-ledger' );
    my $result = $manager->execute_check_messages( 'skills', 1, 0 );
    is( $result->{processed}, 1, 'collector-owned check-message still processes the inbound message when typing status fails' );
    is( $result->{replied}, 1, 'collector-owned check-message still sends the final reply when typing status fails' );
    is( scalar @resume_calls, 1, 'collector-owned check-message still resumes Codex when typing status fails' );
    is( $post_calls[0][0], 'sendChatAction', 'collector-owned check-message attempted the typing action before the reply' );
    is( $post_calls[1][0], 'sendMessage', 'collector-owned check-message still sends the reply after a typing-action failure' );
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
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 104,
                        message   => {
                            message_id => 22,
                            text       => 'Finish all tasks with all gates',
                            chat       => { id => 99, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary, $args ) = @_;
            $args->{on_progress}->('Turn started');
            $args->{on_progress}->('Running command: /bin/bash -lc pwd');
            return 'Reply still sent after progress-stream failure.';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            die "Telegram POST failed for editMessageText: 500 Internal Server Error\n" if $method eq 'editMessageText';
            return {
                ok     => JSON::XS::true,
                result => { message_id => 780 + scalar @post_calls, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
        typing_guard_runner => sub { return sub { return 1 } },
    );
    $manager->write_codex_target_session_id( 'skills', 'session-from-ledger' );
    my $result = $manager->execute_check_messages( 'skills', 1, 0 );
    is( $result->{processed}, 1, 'collector-owned check-message still records the inbound message when Telegram verbose progress edits fail mid-run' );
    is( $result->{replied}, 1, 'collector-owned check-message still sends the final reply when Telegram verbose progress edits fail mid-run' );
    is( scalar @{ $result->{progress_errors} }, 1, 'collector-owned check-message records the non-fatal Telegram verbose progress failure separately from reply errors' );
    like( $result->{progress_errors}[0]{error}, qr/editMessageText: 500 Internal Server Error/, 'collector-owned check-message preserves the Telegram verbose progress failure detail' );
    is( scalar @{ $result->{reply_errors} }, 0, 'collector-owned check-message no longer treats the mid-progress verbose edit failure as a terminal reply error' );
    is( $post_calls[0][0], 'sendChatAction', 'collector-owned check-message still starts typing before the managed reply path' );
    is( $post_calls[1][0], 'sendMessage', 'collector-owned check-message sends the initial verbose trace message before the edit failure' );
    is( $post_calls[2][0], 'editMessageText', 'collector-owned check-message still attempts the later verbose edit that fails non-fatally' );
    is( $post_calls[-1][0], 'sendMessage', 'collector-owned check-message still sends the final Telegram reply after the verbose progress failure' );
    is( $post_calls[-1][1]{text}, 'Reply still sent after progress-stream failure.', 'collector-owned check-message still delivers the Codex final reply after the verbose progress failure' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN               => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR       => $runtime,
            TELEGRAM_CODEX_LISTENER_MODE     => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-emit-dies',
            TELEGRAM_CODEX_AUDIT             => '1',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 911,
                        message   => {
                            message_id => 73,
                            text       => 'Finish all tasks with all gates',
                            chat       => { id => 88, type => 'private' },
                        },
                    },
                ],
            };
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary, $args ) = @_;
            $args->{on_progress}->('step one') if $args->{on_progress};
            return 'Managed final reply after emit failure';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 700 + scalar @post_calls, chat => { id => $params->{chat_id} } },
            };
        },
    );
    {
        no warnings 'redefine';
        local *Telegram::Codex::Manager::start_listener_verbose_reporter = sub {
            return {
                emit   => sub { die "simulated reporter emit death\n" },
                finish => sub { return 1 },
            };
        };
        my $result = $manager->execute_check_messages( 'session-emit-dies', 1, 0 );
        is( $result->{processed}, 1, 'execute_check_messages still processes the update when the verbose reporter emit callback dies' );
        is( $result->{replied}, 1, 'execute_check_messages still delivers the final reply when the verbose reporter emit callback dies' );
        is( scalar @{ $result->{progress_errors} }, 1, 'execute_check_messages records the thrown verbose reporter emit failure as one progress error' );
        like( $result->{progress_errors}[0]{error}, qr/simulated reporter emit death/, 'execute_check_messages exposes the thrown verbose reporter emit failure detail' );
        is( $post_calls[-1][0], 'sendMessage', 'execute_check_messages still sends the final Telegram reply after the verbose reporter emit callback dies' );
    }
    my @rows = grep { defined $_ && $_ ne q{} } split /\n/, $manager->read_text_file( $manager->listener_paths_for_session('session-emit-dies')->{audit_file} );
    my @decoded = map { decode_json($_) } @rows;
    ok(
        scalar( grep { $_->{type} && $_->{type} eq 'progress.emit.failed' && $_->{error} =~ /simulated reporter emit death/ } @decoded ),
        'execute_check_messages records a progress.emit.failed audit row when the verbose reporter emit callback dies',
    );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @resume_calls;
    my @post_calls;
    my @download_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
        },
        get_runner => sub {
            my ( $method, $params ) = @_;
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 103,
                        message   => {
                            message_id => 21,
                            caption    => 'What is in this picture?',
                            chat       => { id => 99, type => 'private' },
                            photo      => [ { file_id => 'small-1' }, { file_id => 'big-photo-1' } ],
                        },
                    },
                ],
            } if $method eq 'getUpdates';
            return {
                ok     => JSON::XS::true,
                result => { file_path => 'photos/image-1.jpg' },
            } if $method eq 'getFile';
            die "unexpected method $method";
        },
        download_runner => sub {
            my ($url) = @_;
            push @download_calls, $url;
            return 'JPEGDATA';
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary ) = @_;
            push @resume_calls, [ $session_id, $prompt, $summary ];
            return 'Photo processed from local file.';
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 779, chat => { id => $params->{chat_id} }, text => $params->{text} },
            };
        },
    );
    $manager->write_codex_target_session_id( 'skills', 'session-from-ledger' );
    my $result = $manager->execute_check_messages( 'skills', 1, 0 );
    is( $result->{processed}, 1, 'collector-owned check-message processes inbound photo messages' );
    is( scalar @download_calls, 1, 'collector-owned check-message downloads inbound managed media before asking Codex to reply' );
    like( $resume_calls[0][1], qr/photo_local_path=.*update-103.*photo-103\.jpg/, 'collector-owned check-message passes the downloaded photo local path into the Codex reply prompt' );
    like( $resume_calls[0][1], qr/already downloaded locally for this active Codex session/i, 'collector-owned check-message tells Codex the downloaded media is locally available' );
    is( $post_calls[-2][1]{text}, 'Photo processed from local file.', 'collector-owned check-message still sends the Codex-generated text reply after downloading photo media' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $photo = File::Spec->catfile( $tmpdir, 'reply.png' );
    my $audio = File::Spec->catfile( $tmpdir, 'reply.mp3' );
    my $doc = File::Spec->catfile( $tmpdir, 'reply.pdf' );
    _write( $photo, 'png' );
    _write( $audio, 'mp3' );
    _write( $doc, 'pdf' );
    my @calls;
    my $manager = new_manager(
        post_runner => sub {
            my ( $method, $params, $files ) = @_;
            push @calls, [ $method, $params, $files ];
            return { ok => JSON::XS::true, result => { message_id => 800 + scalar @calls } };
        },
    );
    $manager->dispatch_listener_reply(
        chat_id             => 55,
        reply_to_message_id => 12,
        reply_message       => "telegram_attachment_type=photo\ntelegram_attachment_path=$photo\ntelegram_attachment_caption=look",
    );
    $manager->dispatch_listener_reply(
        chat_id             => 55,
        reply_to_message_id => 13,
        reply_message       => "telegram_attachment_type=audio\ntelegram_attachment_path=$audio\ntelegram_attachment_caption=listen",
    );
    $manager->dispatch_listener_reply(
        chat_id             => 55,
        reply_to_message_id => 14,
        reply_message       => "telegram_attachment_type=document\ntelegram_attachment_path=$doc\ntelegram_attachment_caption=read",
    );
    is( $calls[0][0], 'sendPhoto', 'dispatch_listener_reply routes photo attachment directives to sendPhoto' );
    is( $calls[0][2]{photo}, $photo, 'dispatch_listener_reply forwards the local photo path' );
    is( $calls[1][0], 'sendAudio', 'dispatch_listener_reply routes audio attachment directives to sendAudio' );
    is( $calls[1][2]{audio}, $audio, 'dispatch_listener_reply forwards the local audio path' );
    is( $calls[2][0], 'sendDocument', 'dispatch_listener_reply routes generic attachment directives to sendDocument' );
    is( $calls[2][2]{document}, $doc, 'dispatch_listener_reply forwards the local document path' );
}

{
    my $manager = new_manager;
    my $prompt = $manager->codex_session_reply_prompt(
        {
            message_id => 55,
            text       => q{},
            caption    => 'media caption',
            chat       => { id => 77 },
            photo      => { file_id => 'photo-1', local_path => '/tmp/photo-1.jpg' },
            document   => { file_id => 'doc-1', file_name => 'report.pdf', mime_type => 'application/pdf', local_path => '/tmp/report.pdf' },
            audio      => { file_id => 'aud-1', title => 'Track', mime_type => 'audio/mpeg', local_path => '/tmp/track.bin' },
            video      => { file_id => 'vid-1', mime_type => 'video/mp4', duration => 9, local_path => '/tmp/video.bin' },
            voice      => { file_id => 'voc-1', mime_type => 'audio/ogg', duration => 4, local_path => '/tmp/voice.bin' },
        }
    );
    like( $prompt, qr/Downloaded Telegram images are attached to this Codex prompt as real image inputs when available\./i, 'codex_session_reply_prompt tells Codex that supported Telegram images are attached as real image inputs' );
    like( $prompt, qr/Non-image files remain available through the local paths below for tool-based inspection\./i, 'codex_session_reply_prompt distinguishes local-path-only media from real image attachments' );
    like( $prompt, qr/already downloaded locally for this active Codex session/i, 'codex_session_reply_prompt tells Codex that local media paths are already downloaded' );
    like( $prompt, qr/Do not claim the attachment was not downloaded/i, 'codex_session_reply_prompt blocks the old metadata-only excuse when local paths exist' );
    like( $prompt, qr/photo_file_id=photo-1/, 'codex_session_reply_prompt includes inbound photo metadata for Telegram media handling' );
    like( $prompt, qr/photo_local_path=\/tmp\/photo-1\.jpg/, 'codex_session_reply_prompt includes inbound photo local path metadata' );
    like( $prompt, qr/document_file_id=doc-1/, 'codex_session_reply_prompt includes inbound document metadata' );
    like( $prompt, qr/document_name=report\.pdf/, 'codex_session_reply_prompt includes inbound document filename metadata' );
    like( $prompt, qr/document_local_path=\/tmp\/report\.pdf/, 'codex_session_reply_prompt includes inbound document local path metadata' );
    like( $prompt, qr/audio_file_id=aud-1/, 'codex_session_reply_prompt includes inbound audio metadata' );
    like( $prompt, qr/audio_local_path=\/tmp\/track\.bin/, 'codex_session_reply_prompt includes inbound audio local path metadata' );
    like( $prompt, qr/video_file_id=vid-1/, 'codex_session_reply_prompt includes inbound video metadata' );
    like( $prompt, qr/video_local_path=\/tmp\/video\.bin/, 'codex_session_reply_prompt includes inbound video local path metadata' );
    like( $prompt, qr/voice_file_id=voc-1/, 'codex_session_reply_prompt includes inbound voice metadata' );
    like( $prompt, qr/voice_local_path=\/tmp\/voice\.bin/, 'codex_session_reply_prompt includes inbound voice local path metadata' );
}

{
    my $manager = new_manager;
    my @paths = $manager->codex_session_image_input_paths(
        {
            photo    => { local_path => '/tmp/photo-1.jpg' },
            document => { file_name => 'preview.png', mime_type => 'image/png', local_path => '/tmp/preview.png' },
            audio    => { local_path => '/tmp/track.mp3' },
            voice    => { local_path => '/tmp/voice.ogg' },
        }
    );
    is_deeply( \@paths, [ '/tmp/photo-1.jpg', '/tmp/preview.png' ], 'codex_session_image_input_paths returns only photo and image-document local paths' );
}

{
    my $manager = new_manager;
    my @paths = $manager->codex_session_image_input_paths(
        {
            document => { file_name => 'Report Final.PDF', mime_type => 'application/pdf', local_path => '/tmp/report.pdf' },
            video    => { local_path => '/tmp/video.mp4' },
        }
    );
    is_deeply( \@paths, [], 'codex_session_image_input_paths excludes non-image local files' );
}

{
    my $manager = new_manager;
    my $prompt = $manager->codex_session_reply_prompt(
        {
            message_id => 77,
            text       => 'Finish all tasks with all gates',
            caption    => q{},
            chat       => { id => 88 },
        }
    );
    like( $prompt, qr/Do the actual work in this resumed Codex session before you reply/i, 'task-style Telegram prompts tell Codex to do the work before replying' );
    like( $prompt, qr/Do not prepend greetings, acknowledgements, or status prefaces/i, 'task-style Telegram prompts block boilerplate prefaces' );
    like( $prompt, qr/Do not send promise-only replies such as .*will be done/i, 'task-style Telegram prompts block promise-only placeholder replies' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_id = '019e-session-sync-demo';
    my $session_dir = File::Spec->catdir( $runtime, '.codex', 'sessions', '2026', '05', '22' );
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T10-00-00-$session_id.jsonl" );
    my @rows = (
        {
            timestamp => '2026-05-22T10:00:00Z',
            type      => 'response_item',
            payload   => {
                type    => 'message',
                role    => 'user',
                content => [
                    {
                        type => 'input_text',
                        text => 'TUI side says hello',
                    },
                ],
            },
        },
        {
            timestamp => '2026-05-22T10:00:10Z',
            type      => 'response_item',
            payload   => {
                type    => 'message',
                role    => 'assistant',
                content => [
                    {
                        type => 'output_text',
                        text => 'TUI side replied hello',
                    },
                ],
            },
        },
        {
            timestamp => '2026-05-22T10:01:00Z',
            type      => 'response_item',
            payload   => {
                type    => 'message',
                role    => 'user',
                content => [
                    {
                        type => 'input_text',
                        text => join(
                            "\n",
                            'A Telegram user sent a message to this active Codex session.',
                            'Reply as this Codex session, using the current conversation context.',
                            'chat_id=398296603',
                            'message_id=77',
                            'text=Telegram asks here',
                            'caption=',
                        ),
                    },
                ],
            },
        },
    );
    _write( $session_file, join( q{}, map { encode_json($_) . "\n" } @rows ) );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_CODEX_TARGET_SESSION_ID => $session_id,
            TELEGRAM_CODEX_SESSION_ID        => 'skills',
        },
    );
    my @messages = $manager->codex_session_recent_messages($session_id);
    is( $messages[0]{text}, 'TUI side says hello', 'codex_session_recent_messages keeps normal TUI user messages' );
    is( $messages[1]{text}, 'TUI side replied hello', 'codex_session_recent_messages keeps normal TUI assistant messages' );
    is( $messages[2]{text}, "[Telegram chat 398296603 message 77]\nTelegram asks here", 'codex_session_recent_messages normalizes old raw Telegram bridge prompts into readable transcript lines' );
    my $prompt = $manager->codex_session_reply_prompt(
        {
            message_id => 88,
            text       => 'Please continue from Telegram',
            caption    => q{},
            chat       => { id => 398296603 },
        }
    );
    like( $prompt, qr/Recent shared Codex session transcript:/, 'codex_session_reply_prompt includes recent persisted Codex transcript context' );
    like( $prompt, qr/user: TUI side says hello/, 'codex_session_reply_prompt carries recent TUI-side user history into Telegram replies' );
    like( $prompt, qr/assistant: TUI side replied hello/, 'codex_session_reply_prompt carries recent TUI-side assistant history into Telegram replies' );
    like( $prompt, qr/user: \[Telegram chat 398296603 message 77\]\nTelegram asks here/, 'codex_session_reply_prompt carries normalized older Telegram turns too' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $runtime, '.codex', 'sessions', '2026', '05', '22' );
    make_path($session_dir);
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
    );
    is( $manager->codex_session_transcript_path('019e-session-missing'), undef, 'codex_session_transcript_path returns undef when the Codex session tree exists but no matching transcript file is present' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_id = '019e-session-sync-write';
    my $session_dir = File::Spec->catdir( $runtime, '.codex', 'sessions', '2026', '05', '22' );
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T10-00-00-$session_id.jsonl" );
    _write( $session_file, q{} );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
    );
    my $summary = {
        message_id => 99,
        text       => 'Telegram asks from phone',
        caption    => q{},
        chat       => { id => 398296603 },
        document   => { file_name => 'report.pdf', local_path => '/tmp/report.pdf' },
    };
    ok( $manager->sync_telegram_exchange_to_codex_session( $session_id, $summary, 'Reply sent back to Telegram' ), 'sync_telegram_exchange_to_codex_session appends Telegram exchange rows into the target Codex session transcript' );
    ok( !$manager->sync_telegram_exchange_to_codex_session( $session_id, $summary, 'Reply sent back to Telegram' ), 'sync_telegram_exchange_to_codex_session deduplicates the same Telegram message marker on later runs' );
    my $content = $manager->read_text_file($session_file);
    like( $content, qr/\[Telegram chat 398296603 message 99\]\\nTelegram asks from phone\\n\[document\] \/tmp\/report\.pdf/s, 'sync_telegram_exchange_to_codex_session appends a readable Telegram user message into the Codex session file' );
    like( $content, qr/\[Telegram reply chat 398296603 message 99\]\\nReply sent back to Telegram/s, 'sync_telegram_exchange_to_codex_session appends the Telegram-facing assistant reply into the Codex session file' );
}

{
    my $manager = new_manager;
    my @lines = $manager->telegram_session_media_summary_lines(
        {
            photo => { local_path => '/tmp/photo.png' },
            audio => { title => 'demo tone' },
            video => { file_id => 'video-file-id' },
            voice => { file_id => 'voice-file-id' },
        }
    );
    is_deeply(
        \@lines,
        [
            '[photo] /tmp/photo.png',
            '[audio] demo tone',
            '[video] video-file-id',
            '[voice] voice-file-id',
        ],
        'telegram_session_media_summary_lines covers photo, audio, video, and voice attachment summary rows'
    );
}

{
    my $manager = new_manager;
    my @descriptors = $manager->summary_media_descriptors(
        {
            update_id => 500,
            document  => { file_id => 'doc-x', file_name => 'Quarterly Report (Final).pdf' },
            audio     => { file_id => 'aud-x', title => 'Track 01 / Intro' },
        }
    );
    is( $descriptors[0]{filename}, 'Quarterly-Report-Final-.pdf', 'summary_media_descriptors sanitizes inbound document filenames through safe_filename' );
    is( $descriptors[1]{filename}, 'Track-01-Intro.bin', 'summary_media_descriptors sanitizes inbound audio titles through safe_filename' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $runtime, 'bin' );
    make_path($bin_dir);
    my $args_file = File::Spec->catfile( $runtime, 'resume.args' );
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex-real' );
    _write( $real_codex, <<"EOF" );
#!/bin/sh
OUT=""
PREV=""
for ARG in "\$@"; do
  if [ "\$PREV" = "--output-last-message" ]; then
    OUT="\$ARG"
  fi
  PREV="\$ARG"
done
printf '%s\n' "\$@" > "$args_file"
printf '%s\n' '{"type":"thread.started"}'
printf '%s\n' '{"type":"turn.started"}'
printf '%s\n' '{"type":"item.started","item":{"type":"command_execution","command":"/bin/pwd"}}'
printf '%s\n' '{"type":"item.completed","item":{"type":"command_execution","command":"/bin/pwd","exit_code":0,"aggregated_output":"/tmp\\n"}}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"Inspecting the local file"}}'
printf '  Live Codex Telegram reply.  ' > "\$OUT"
exit 0
EOF
    chmod 0755, $real_codex or die "Unable to chmod fake real codex resume binary: $!";
    my @progress;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            VERSION                         => '0.30',
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR      => $runtime,
            CODEX_SESSION_ID                => 'session-real-resume',
            TELEGRAM_CODEX_LISTENER_MODE    => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-real-resume',
            CODEX_REAL_BIN                  => $real_codex,
        },
    );
    my $reply = $manager->codex_session_reply_for_update(
        {
            message_id => 14,
            text       => 'hello from telegram',
            chat       => { id => 88, type => 'private' },
            photo      => { file_id => 'photo-1', local_path => '/tmp/real-photo.jpg' },
            document   => { file_id => 'doc-1', file_name => 'preview.png', mime_type => 'image/png', local_path => '/tmp/preview.png' },
            voice      => { file_id => 'voc-1', local_path => '/tmp/voice.ogg' },
        },
        on_progress => sub { push @progress, @_ },
    );
    is( $reply, 'Live Codex Telegram reply.', 'codex_session_reply_for_update uses the real codex exec resume path and trims the generated reply text' );
    my $args = do {
        open my $fh, '<', $args_file or die $!;
        local $/;
        <$fh>;
    };
    like( $args, qr/^exec\n--dangerously-bypass-approvals-and-sandbox\nresume\n--skip-git-repo-check\n--json\n--output-last-message\n/m, 'codex_session_reply_for_update invokes codex exec resume with the bypass flag, json stream, and output capture file' );
    like( $args, qr/\n-i\n\/tmp\/real-photo\.jpg\n/s, 'codex_session_reply_for_update attaches Telegram photo local paths as real image inputs to codex exec resume' );
    like( $args, qr/\n-i\n\/tmp\/preview\.png\n/s, 'codex_session_reply_for_update attaches image documents as real image inputs to codex exec resume' );
    unlike( $args, qr/\n-i\n\/tmp\/voice\.ogg\n/s, 'codex_session_reply_for_update does not pass non-image media as fake image inputs' );
    like( $args, qr/session-real-resume/, 'codex_session_reply_for_update targets the managed session id when it runs the real codex binary' );
    is_deeply(
        \@progress,
        [
            'Session resumed',
            'Turn started',
            'Running command: /bin/pwd',
            'Command finished (exit 0): /bin/pwd',
            'Output: /tmp',
            'Agent: Inspecting the local file',
        ],
        'codex_session_reply_for_update streams real codex json events through the progress callback',
    );
    like( $manager->{ua}->agent, qr/\Atelegram-codex\/0\.30\z/, 'manager user agent tracks the current skill version' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $runtime, 'bin' );
    make_path($bin_dir);
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex-real' );
    _write( $real_codex, <<"EOF" );
#!/bin/sh
echo "provider socket closed unexpectedly" >&2
exit 7
EOF
    chmod 0755, $real_codex or die "Unable to chmod fake failing real codex resume binary: $!";
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR      => $runtime,
            TELEGRAM_CODEX_LISTENER_MODE    => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-real-resume',
            CODEX_REAL_BIN                  => $real_codex,
        },
    );
    my $error = eval {
        $manager->codex_session_reply_for_update(
            {
                message_id => 18,
                text       => 'hello from telegram',
                chat       => { id => 88, type => 'private' },
            }
        );
        1;
    } ? q{} : $@;
    like( $error, qr/Codex resume returned an empty Telegram reply \(exit=7 signal=0\)/, 'codex_session_reply_for_update reports the real exit status when the managed codex resume subprocess fails before writing a reply' );
    like( $error, qr/provider socket closed unexpectedly/, 'codex_session_reply_for_update includes stderr tail detail from the failed managed codex resume subprocess' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $runtime, 'bin' );
    make_path($bin_dir);
    my $real_codex = File::Spec->catfile( $bin_dir, 'codex-real' );
    _write( $real_codex, <<"EOF" );
#!/bin/sh
OUT=""
PREV=""
for ARG in "\$@"; do
  if [ "\$PREV" = "--output-last-message" ]; then
    OUT="\$ARG"
  fi
  PREV="\$ARG"
done
printf '%s\n' '{"type":"turn.started"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"Long task step"}}'
printf 'Final answer after progress callback failure' > "\$OUT"
exit 0
EOF
    chmod 0755, $real_codex or die "Unable to chmod fake callback-failing real codex resume binary: $!";
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN               => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR       => $runtime,
            TELEGRAM_CODEX_LISTENER_MODE     => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-callback-failure',
            TELEGRAM_CODEX_AUDIT             => '1',
            CODEX_REAL_BIN                   => $real_codex,
        },
    );
    my $reply = $manager->codex_session_reply_for_update(
        {
            message_id => 41,
            text       => 'Finish all tasks with all gates',
            chat       => { id => 88, type => 'private' },
        },
        on_progress => sub { die "progress callback blew up\n" },
    );
    is( $reply, 'Final answer after progress callback failure', 'codex_session_reply_for_update still returns the final reply when the progress callback dies' );
    my @rows = grep { defined $_ && $_ ne q{} } split /\n/, $manager->read_text_file( $manager->listener_paths->{audit_file} );
    my @decoded = map { decode_json($_) } @rows;
    ok(
        scalar( grep { $_->{type} && $_->{type} eq 'codex.progress.callback_failed' && $_->{error} =~ /progress callback blew up/ } @decoded ),
        'codex_session_reply_for_update records a codex.progress.callback_failed audit event when the progress callback dies',
    );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my @resume_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN              => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR      => $runtime,
            CODEX_SESSION_ID                => 'skills',
            TELEGRAM_CODEX_SESSION_ID       => 'skills',
            TELEGRAM_CODEX_LISTENER_MODE    => 'codex-session',
            TELEGRAM_CODEX_TARGET_SESSION_ID => 'session-real-resume',
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary ) = @_;
            push @resume_calls, [ $session_id, $prompt, $summary ];
            return @resume_calls == 1 ? 'Will be done.' : 'Done. All requested tasks are now complete.';
        },
    );
    my $reply = $manager->codex_session_reply_for_update(
        {
            message_id => 15,
            text       => 'Finish all tasks with all gates',
            chat       => { id => 88, type => 'private' },
        }
    );
    is( scalar @resume_calls, 2, 'codex_session_reply_for_update retries once when the first task reply is only a promise placeholder' );
    like( $resume_calls[1][1], qr/The prior reply was only a promise or progress update/i, 'codex_session_reply_for_update uses a stricter retry prompt after a promise-only reply' );
    is( $reply, 'Done. All requested tasks are now complete.', 'codex_session_reply_for_update returns the stricter retry result instead of the placeholder promise' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $home, '.developer-dashboard', 'config' );
    make_path($config_root);
    _write(
        File::Spec->catfile( $config_root, 'codex.json' ),
        encode_json(
            {
                talbot       => 'session-talbot-42',
                _last_action => 'Add talbot',
                _last_update => '2026-05-21 08:00:00',
            }
        ),
    );
    my @resume_calls;
    my $manager = new_manager(
        cwd  => File::Spec->catdir( $home, 'skills' ),
        home => $home,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => '~/.telegram-codex',
            TELEGRAM_CODEX_SESSION_ID  => 'skills',
            CODEX_SESSION_ID           => 'skills',
            TICKET_REF                 => 'talbot',
        },
        codex_resume_runner => sub {
            my ( $session_id, $prompt, $summary ) = @_;
            push @resume_calls, [ $session_id, $prompt, $summary ];
            return 'Mapped saved-session reply.';
        },
    );
    my $reply = $manager->codex_session_reply_for_update(
        {
            message_id => 16,
            text       => 'status?',
            chat       => { id => 99, type => 'private' },
        }
    );
    is( $resume_calls[0][0], 'session-talbot-42', 'codex_session_reply_for_update falls back to codex.json saved-session mapping when codex.session is missing' );
    is( $reply, 'Mapped saved-session reply.', 'codex_session_reply_for_update returns the mapped-session response' );
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
    my @sleep_calls;
    my $get_call_count = 0;
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-get-retry',
        },
        get_runner => sub {
            my ( $method, $params ) = @_;
            $get_call_count++;
            die "Telegram GET failed for getUpdates: 500 Status read failed: Connection reset by peer\n" if $get_call_count == 1;
            return {
                ok     => JSON::XS::true,
                result => $get_call_count == 2
                  ? [
                        {
                            update_id => 71,
                            message   => {
                                message_id => 10,
                                text       => 'hello',
                                chat       => { id => 88, type => 'private' },
                            },
                        },
                    ]
                  : [],
            };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => { message_id => 400 + scalar @post_calls, chat => { id => $params->{chat_id} } },
            };
        },
        sleep_runner => sub {
            my ($seconds) = @_;
            push @sleep_calls, $seconds;
        },
    );
    my $result = $manager->execute_listen( 3, 0, 'listener ack' );
    is( $result->{processed}, 1, 'listen survives a transient getUpdates transport failure and still processes later messages' );
    is( $result->{replied}, 1, 'listen still replies after recovering from a transient getUpdates transport failure' );
    is( scalar @{ $result->{get_errors} }, 1, 'listen reports the transient getUpdates transport failure' );
    is( $result->{get_errors}[0]{cycle}, 0, 'listen records the failed cycle index for the transient getUpdates transport failure' );
    is( scalar @sleep_calls, 1, 'listen pauses once before retrying after a transient getUpdates transport failure' );
    is( $manager->read_text_file( $result->{offset_file} ), "72\n", 'listen still advances and persists the next offset after recovering from a transient getUpdates transport failure' );
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
            CODEX_SESSION_ID                     => 'session-prime-then-capture',
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
    is( $result->{replied}, 0, 'prime-latest auto-start does not auto-reply by default after priming' );
    is( $manager->read_text_file( $result->{offset_file} ), "103\n", 'prime-latest auto-start advances offset after the new message cycle' );
    is( scalar @post_calls, 0, 'prime-latest auto-start only captures the new message unless a reply text is explicitly provided' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $runtime, 'session-skip-duplicate' );
    mkdir $session_dir;
    _write(
        File::Spec->catfile( $session_dir, 'listener.inbox.jsonl' ),
        encode_json(
            {
                update_id  => 500,
                message_id => 21,
                text       => 'already seen',
            }
        ) . "\n",
    );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-skip-duplicate',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    {
                        update_id => 500,
                        message   => {
                            message_id => 21,
                            text       => 'already seen',
                            chat       => { id => 88, type => 'private' },
                        },
                    },
                ],
            };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return { ok => JSON::XS::true, result => { message_id => 61 } };
        },
    );
    my $result = $manager->execute_listen( 1, 0, 'listener ack' );
    is( $result->{processed}, 0, 'listen skips an update already present in the session inbox ledger' );
    is( $result->{replied}, 0, 'listen does not reply again for an update already present in the session inbox ledger' );
    is( scalar @post_calls, 0, 'listen suppresses duplicate reply sends for an already-recorded update' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $polls = 0;
    my $slept = 0;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-zero-means-forever',
        },
        get_runner => sub {
            $polls++;
            die "forced listener stop\n" if $polls > 1;
            return { ok => JSON::XS::true, result => [] };
        },
        sleep_runner => sub {
            $slept++;
            die "listener paused after retry\n";
        },
    );
    my $error = eval { $manager->execute_listen( 0, 0 ); 1 } ? q{} : $@;
    like( $error, qr/listener paused after retry/, 'listen treats MAX_CYCLES=0 as run forever instead of exiting after the first cycle' );
    is( $polls, 2, 'listen performs another poll cycle before external stop when MAX_CYCLES=0 is passed' );
    is( $slept, 1, 'listen reaches the retry pause path instead of terminating immediately when MAX_CYCLES=0 is passed' );
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
    my $session_dir = File::Spec->catdir( $runtime, 'session-recover' );
    mkdir $session_dir;
    _write(
        File::Spec->catfile( $session_dir, 'listener.inbox.jsonl' ),
        join(
            "\n",
            encode_json( { update_id => 120, text => 'old-1' } ),
            encode_json( { update_id => 121, text => 'old-2' } ),
            q{},
        ),
    );
    my @get_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-recover',
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
    is( $result->{processed}, 0, 'listen can recover an offset from the inbox ledger when the offset file is missing' );
    is( $get_calls[0][1]{offset}, 122, 'listen resumes from the recovered next offset when only the inbox ledger exists' );
    is( $manager->read_text_file( File::Spec->catfile( $session_dir, 'listener.offset' ) ), "122\n", 'listen persists the recovered next offset back to listener.offset when the file was missing' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $runtime, 'session-recover-newer' );
    mkdir $session_dir;
    _write( File::Spec->catfile( $session_dir, 'listener.offset' ), "50\n" );
    _write(
        File::Spec->catfile( $session_dir, 'listener.inbox.jsonl' ),
        join(
            "\n",
            encode_json( { update_id => 120, text => 'old-1' } ),
            encode_json( { update_id => 121, text => 'old-2' } ),
            q{},
        ),
    );
    my @get_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-recover-newer',
        },
        get_runner => sub {
            my ( $method, $params ) = @_;
            push @get_calls, [ $method, $params ];
            return { ok => JSON::XS::true, result => [] };
        },
    );
    my $result = $manager->execute_listen( 1, 0, 'listener ack' );
    is( $result->{processed}, 0, 'listen handles stale stored offsets cleanly when the inbox ledger proves a newer offset' );
    is( $get_calls[0][1]{offset}, 122, 'listen advances to the newer recovered inbox offset instead of replaying from an older stored offset' );
    is( $manager->read_text_file( File::Spec->catfile( $session_dir, 'listener.offset' ) ), "122\n", 'listen rewrites listener.offset to the newer recovered inbox offset before polling' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $runtime, 'session-recover-invalid' );
    mkdir $session_dir;
    _write(
        File::Spec->catfile( $session_dir, 'listener.inbox.jsonl' ),
        join(
            "\n",
            'not-json-at-all',
            encode_json( { text => 'missing update id' } ),
            q{},
        ),
    );
    my @get_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-recover-invalid',
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
    is( $result->{processed}, 0, 'listen handles an invalid inbox ledger without crashing when no offset file exists' );
    ok( !exists $get_calls[0][1]{offset}, 'listen leaves the offset unset when inbox recovery finds no valid update id' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $session_dir = File::Spec->catdir( $runtime, 'session-skip-stale' );
    mkdir $session_dir;
    _write( File::Spec->catfile( $session_dir, 'listener.offset' ), "50\n" );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $runtime,
        home => $runtime,
        env  => {
            TELEGRAM_BOT_TOKEN         => 'token-xyz',
            TELEGRAM_CODEX_RUNTIME_DIR => $runtime,
            CODEX_SESSION_ID           => 'session-skip-stale',
        },
        get_runner => sub {
            return {
                ok     => JSON::XS::true,
                result => [
                    { update_id => 48, message => { message_id => 1, text => 'too old', chat => { id => 88, type => 'private' } } },
                    { update_id => 49, message => { message_id => 2, text => 'still old', chat => { id => 88, type => 'private' } } },
                    { update_id => 50, message => { message_id => 3, text => 'current', chat => { id => 88, type => 'private' } } },
                    { update_id => 51, message => { message_id => 4, text => 'newer', chat => { id => 88, type => 'private' } } },
                ],
            };
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return { ok => JSON::XS::true, result => { message_id => 300 + scalar @post_calls } };
        },
    );
    my $result = $manager->execute_listen( 1, 0, 'listener ack' );
    is( $result->{processed}, 2, 'listen skips stale returned updates that are older than the next stored offset' );
    is( $result->{replied}, 2, 'listen only replies to non-stale updates' );
    is( $manager->read_text_file( $result->{offset_file} ), "52\n", 'listen still advances offset after the non-stale updates' );
    my @entries = split /\n/, $manager->read_text_file( $result->{inbox_file} );
    is( scalar @entries, 2, 'listen appends only the non-stale updates to the inbox ledger' );
    is( decode_json( $entries[0] )->{update_id}, 50, 'listen keeps the first current update' );
    is( decode_json( $entries[1] )->{update_id}, 51, 'listen keeps the newer update' );
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
    my $manager = new_manager;
    is( $manager->listener_pause_seconds(0), 0, 'listener_pause_seconds returns after the direct sleep path without requiring an injected sleep runner' );
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
    is(
        $manager->telegram_get( 'getFile', { file_id => 'photo-123', offset => 9 } )->{result}{sent},
        1,
        'telegram_get returns payload for parameterized GET requests',
    );
    is( $manager->telegram_post( 'sendMessage', { chat_id => 9 } )->{result}{sent}, 1, 'telegram_post uses UA request path' );
    is( $manager->telegram_post_file( 'sendDocument', { chat_id => 9 }, { document => $doc } )->{result}{uploaded}, 1, 'telegram_post_file uses multipart request path' );
    is( $manager->telegram_download('files/doc.txt'), 'FILEDATA', 'telegram_download uses UA get path' );
    is( $ua->{requests}[0]->method, 'GET', 'telegram_get sends GET request' );
    like( $ua->{requests}[1]->uri->query, qr/(?:^|&)file_id=photo-123(?:&|$)/, 'telegram_get encodes file_id into the query string' );
    like( $ua->{requests}[1]->uri->query, qr/(?:^|&)offset=9(?:&|$)/, 'telegram_get encodes numeric parameters into the query string' );
    ok( !$ua->{requests}[1]->header('File-Id'), 'telegram_get does not mis-send file_id as a header' );
    is( $ua->{requests}[2]->method, 'POST', 'telegram_post sends POST request' );
    is( $ua->{requests}[3]->method, 'POST', 'telegram_post_file sends multipart POST request' );
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

{
    my $manager = new_manager(
        process_list_runner => sub {
            return [
                {
                    pid => 1920363,
                    tty => 'pts/34',
                    cmd => '/opt/codex/bin/codex resume 019e-live-shared-session',
                },
            ];
        },
        tmux_panes_runner => sub {
            return [
                {
                    pane_id => '%118',
                    tty     => '/dev/pts/34',
                },
            ];
        },
    );
    is( $manager->discover_codex_session_tty('019e-live-shared-session'), 'pts/34', 'discover_codex_session_tty finds the tty for the live shared Codex session' );
    is( $manager->resolve_codex_live_tmux_pane('019e-live-shared-session'), '%118', 'resolve_codex_live_tmux_pane maps the live shared Codex session to its tmux pane' );
}

{
    my @sent;
    my $manager = new_manager(
        tmux_send_runner => sub {
            my ( $pane_id, $text ) = @_;
            push @sent, [ $pane_id, $text ];
            return 1;
        },
    );
    ok( $manager->tmux_send_text_to_pane( '%118', 'Remember this code abc:foo' ), 'tmux_send_text_to_pane succeeds through the injected tmux sender' );
    is_deeply( \@sent, [ [ '%118', 'Remember this code abc:foo' ] ], 'tmux_send_text_to_pane forwards the pane id and literal text to tmux' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $cwd = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-pane-session';
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-30-00-$session_id.jsonl" );
    _write( $session_file, q{} );
    my @progress;
    my $manager = new_manager(
        cwd  => $cwd,
        home => $home,
        env  => {
            TELEGRAM_CODEX_TARGET_SESSION_ID => $session_id,
        },
        process_list_runner => sub {
            return [
                {
                    pid => 1920363,
                    tty => 'pts/34',
                    cmd => "/opt/codex/bin/codex resume $session_id",
                },
            ];
        },
        tmux_panes_runner => sub {
            return [
                {
                    pane_id => '%118',
                    tty     => '/dev/pts/34',
                },
            ];
        },
        tmux_send_runner => sub {
            my ( $pane_id, $text ) = @_;
            open my $fh, '>>', $session_file or die "Unable to append $session_file: $!";
            print {$fh} encode_json(
                {
                    timestamp => '2026-05-22T18:30:01Z',
                    type      => 'response_item',
                    payload   => {
                        type    => 'message',
                        role    => 'user',
                        content => [
                            {
                                type => 'input_text',
                                text => $text,
                            },
                        ],
                    },
                }
            ) . "\n";
            print {$fh} encode_json(
                {
                    timestamp => '2026-05-22T18:30:02Z',
                    type      => 'response_item',
                    payload   => {
                        type    => 'message',
                        role    => 'assistant',
                        phase   => 'commentary',
                        content => [
                            {
                                type => 'output_text',
                                text => 'Checking the live shared Codex session now.',
                            },
                        ],
                    },
                }
            ) . "\n";
            print {$fh} encode_json(
                {
                    timestamp => '2026-05-22T18:30:03Z',
                    type      => 'response_item',
                    payload   => {
                        type    => 'message',
                        role    => 'assistant',
                        phase   => 'final_answer',
                        content => [
                            {
                                type => 'output_text',
                                text => 'Final live shared Codex reply.',
                            },
                        ],
                    },
                }
            ) . "\n";
            close $fh or die "Unable to close $session_file: $!";
            return 1;
        },
        codex_resume_runner => sub { die "live pane path should not fall back to codex exec resume\n" },
        sleep_runner        => sub { return 0 },
    );
    my $reply = $manager->codex_session_reply_for_update(
        {
            text       => 'Remember this code abc:foo',
            chat       => { id => 398296603 },
            message_id => 91,
        },
        on_progress => sub {
            my ($line) = @_;
            push @progress, $line;
            return 1;
        },
    );
    is( $reply, 'Final live shared Codex reply.', 'codex_session_reply_for_update returns the final assistant reply from the shared live transcript when a live tmux pane exists' );
    is_deeply( \@progress, [ 'Checking the live shared Codex session now.' ], 'codex_session_reply_for_update streams commentary rows from the shared live transcript as progress' );
    my $cursor_file = $manager->listener_paths->{transcript_cursor_file};
    ok( -f $cursor_file, 'codex_session_reply_for_update records the shared transcript cursor after consuming a live pane turn' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $cwd = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-fallback';
    my $runtime_dir = File::Spec->catdir( $home, '.telegram-codex', 'skills' );
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($runtime_dir);
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-31-00-$session_id.jsonl" );
    _write( $session_file, q{} );
    my @resume_calls;
    my @sleep_calls;
    my $manager = new_manager(
        cwd  => $cwd,
        home => $home,
        env  => {
            TELEGRAM_CODEX_SESSION_ID        => 'skills',
            TELEGRAM_CODEX_TARGET_SESSION_ID => $session_id,
            TELEGRAM_CODEX_AUDIT             => '1',
        },
        process_list_runner => sub {
            return [
                {
                    pid    => 44,
                    tty    => 'pts/0',
                    etimes => 90_000,
                    cmd    => "codex resume $session_id",
                },
            ];
        },
        tmux_panes_runner => sub {
            return [
                {
                    pane_id         => '%77',
                    tty             => '/dev/pts/0',
                    current_command => 'node',
                },
            ];
        },
        tmux_send_runner => sub { return 1 },
        sleep_runner     => sub { push @sleep_calls, 1; return 0 },
        codex_resume_runner => sub {
            my ( $sid, $prompt ) = @_;
            push @resume_calls, [ $sid, $prompt ];
            return 'Detached fallback reply.';
        },
    );
    my $reply = $manager->codex_session_reply_for_update(
        {
            text       => 'Test live pane fallback',
            chat       => { id => 398296603 },
            message_id => 92,
        },
    );
    is( $manager->resolve_codex_live_tmux_pane($session_id), '%77', 'codex_session_reply_for_update fallback test resolves the live pane first' );
    is( $reply, 'Detached fallback reply.', 'codex_session_reply_for_update falls back to detached resume when the live pane never records the injected turn' );
    is( scalar @resume_calls, 1, 'codex_session_reply_for_update retries through the detached resume path after live pane failure' );
    ok( !-f $manager->listener_paths->{transcript_cursor_file}, 'codex_session_reply_for_update fallback test does not falsely record a completed live transcript cursor' );
    my $audit = $manager->read_text_file( $manager->listener_paths->{audit_file} );
    like( $audit, qr/"type":"codex\.live_pane\.fallback"/, 'codex_session_reply_for_update records the live-pane fallback audit event' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $cwd = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-outbound-session';
    my $runtime_dir = File::Spec->catdir( $home, '.telegram-codex', 'skills' );
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($runtime_dir);
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-31-00-$session_id.jsonl" );
    _write(
        $session_file,
        join(
            "\n",
            encode_json(
                {
                    timestamp => '2026-05-22T18:31:01Z',
                    type      => 'response_item',
                    payload   => {
                        type    => 'message',
                        role    => 'user',
                        content => [
                            {
                                type => 'input_text',
                                text => 'Please tighten these tests.',
                            },
                        ],
                    },
                }
            ),
            encode_json(
                {
                    timestamp => '2026-05-22T18:31:02Z',
                    type      => 'response_item',
                    payload   => {
                        type    => 'message',
                        role    => 'assistant',
                        phase   => 'commentary',
                        content => [
                            {
                                type => 'output_text',
                                text => 'Reviewing the current test suite now.',
                            },
                        ],
                    },
                }
            ),
            encode_json(
                {
                    timestamp => '2026-05-22T18:31:03Z',
                    type      => 'response_item',
                    payload   => {
                        type    => 'message',
                        role    => 'assistant',
                        phase   => 'final_answer',
                        content => [
                            {
                                type => 'output_text',
                                text => 'Tests tightened and rerun.',
                            },
                        ],
                    },
                }
            ),
            q{},
        ),
    );
    _write(
        File::Spec->catfile( $runtime_dir, 'pairing.json' ),
        encode_json( { paired_chat_id => 398296603 } ),
    );
    _write(
        File::Spec->catfile( $runtime_dir, 'codex.session' ),
        "$session_id\n",
    );
    _write(
        File::Spec->catfile( $runtime_dir, 'transcript.cursor' ),
        "0\n",
    );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $cwd,
        home => $home,
        env  => {
            TELEGRAM_CODEX_SESSION_ID => 'skills',
        },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            return {
                ok     => JSON::XS::true,
                result => {
                    message_id => 700 + scalar @post_calls,
                    chat       => { id => $params->{chat_id} },
                },
            };
        },
    );
    my %state;
    my $paths = $manager->listener_paths_for_session('skills');
    is( $manager->process_tui_live_outbound_transcript( 'skills', $paths, \%state ), 3, 'process_tui_live_outbound_transcript consumes new transcript rows for a paired chat' );
    is( $post_calls[0][0], 'sendChatAction', 'process_tui_live_outbound_transcript sends typing to Telegram for a TUI-originated turn' );
    is( $post_calls[1][0], 'sendMessage', 'process_tui_live_outbound_transcript sends the initial verbose trace to Telegram for a TUI-originated turn' );
    like( $post_calls[1][1]{text}, qr/Codex verbose/, 'process_tui_live_outbound_transcript starts the Telegram verbose trace for a TUI-originated turn' );
    is( $post_calls[2][0], 'editMessageText', 'process_tui_live_outbound_transcript edits the verbose trace with commentary progress' );
    is( $post_calls[-1][0], 'sendMessage', 'process_tui_live_outbound_transcript sends the final assistant reply back to Telegram' );
    is( $post_calls[-1][1]{text}, 'Tests tightened and rerun.', 'process_tui_live_outbound_transcript returns the final assistant reply text to Telegram' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($bin_dir);
    my $ps = File::Spec->catfile( $bin_dir, 'ps' );
    _write(
        $ps,
        "#!/bin/sh\nprintf '  11 ? 1 helper --noop\\n  22 pts/77 3 codex resume 019e-real-tty\\n'\n"
    );
    chmod 0755, $ps or die "Unable to chmod fake ps helper: $!";
    local $ENV{PATH} = $bin_dir;
    my $manager = new_manager(
        cwd  => $home,
        home => $home,
        tmux_panes_runner => sub {
            return [
                {
                    pane_id         => '%118',
                    tty             => '/dev/pts/77',
                    current_command => 'node',
                },
            ];
        },
    );
    is( $manager->discover_codex_session_tty('019e-real-tty'), 'pts/77', 'discover_codex_session_tty uses the real ps branch and skips unrelated or ttyless rows' );
    my @rows = $manager->codex_process_rows;
    is( $rows[1]{cmd}, 'codex resume 019e-real-tty', 'codex_process_rows parses ps output through the default branch' );
    is( $rows[1]{etimes}, 3, 'codex_process_rows parses elapsed seconds through the default branch' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $home, 'bin' );
    make_path($bin_dir);
    my $tmux = File::Spec->catfile( $bin_dir, 'tmux' );
    my $log = File::Spec->catfile( $home, 'tmux-send.log' );
    _write(
        $tmux,
        <<"EOF"
#!/bin/sh
if [ "\$1" = "list-panes" ]; then
  printf '%%118\t/dev/pts/77\tnode\n'
  exit 0
fi
if [ "\$1" = "send-keys" ]; then
  printf '%s|' "\$@" >> "$log"
  printf '\n' >> "$log"
  exit 0
fi
exit 1
EOF
    );
    chmod 0755, $tmux or die "Unable to chmod fake tmux helper: $!";
    local $ENV{PATH} = $bin_dir;
    my $manager = new_manager( cwd => $home, home => $home );
    my @panes = $manager->tmux_pane_rows;
    is( $panes[0]{pane_id}, '%118', 'tmux_pane_rows uses the real tmux list-panes branch' );
    is( $manager->discover_tmux_pane_for_tty('pts/77'), '%118', 'discover_tmux_pane_for_tty matches a tty without a /dev prefix' );
    ok( !defined $manager->discover_tmux_pane_for_tty('pts/99'), 'discover_tmux_pane_for_tty returns undef when no tmux pane matches the tty' );
    ok( $manager->tmux_send_text_to_pane( '%118', 'Remember this code abc:foo' ), 'tmux_send_text_to_pane uses the real tmux send-keys branch' );
    my $send_log = do {
        open my $fh, '<', $log or die $!;
        local $/;
        <$fh>;
    };
    like( $send_log, qr/send-keys\|-t\|%118\|-l\|--\|Remember this code abc:foo\|/, 'tmux_send_text_to_pane sends literal text to the target pane' );
    like( $send_log, qr/send-keys\|-t\|%118\|Enter\|/, 'tmux_send_text_to_pane sends Enter to submit the injected text' );
}

{
    my $manager = new_manager(
        process_list_runner => sub {
            return [
                {
                    pid    => 100,
                    tty    => 'pts/34',
                    etimes => 30_000,
                    cmd    => 'codex resume 019e-prefer-newest',
                },
                {
                    pid    => 200,
                    tty    => 'pts/0',
                    etimes => 10,
                    cmd    => 'codex resume 019e-prefer-newest',
                },
            ];
        },
        tmux_panes_runner => sub {
            return [
                { pane_id => '%118', tty => '/dev/pts/34', current_command => 'node' },
                { pane_id => '%77',  tty => '/dev/pts/0',  current_command => 'node' },
            ];
        },
    );
    is( $manager->discover_codex_session_tty('019e-prefer-newest'), 'pts/0', 'discover_codex_session_tty prefers the freshest matching codex resume process' );
    is( $manager->resolve_codex_live_tmux_pane('019e-prefer-newest'), '%77', 'resolve_codex_live_tmux_pane maps the freshest matching codex resume process to its tmux pane' );
}

{
    my $manager = new_manager;
    my $prompt = $manager->codex_live_pane_prompt(
        {
            text    => 'Check this image',
            caption => 'latest upload',
            photo   => { local_path => '/tmp/photo.png' },
            audio   => { title => 'tone' },
        }
    );
    like( $prompt, qr/\ACheck this image\n\[caption\] latest upload\n/s, 'codex_live_pane_prompt starts with the text and caption when both are present' );
    like( $prompt, qr/Any \*_local_path values below are already downloaded locally for this active Codex session\./, 'codex_live_pane_prompt includes the downloaded-local preface when media exists' );
    like( $prompt, qr/\[photo\] \/tmp\/photo\.png/, 'codex_live_pane_prompt includes media summary lines for downloaded files' );
    like( $prompt, qr/\[audio\] tone/, 'codex_live_pane_prompt includes non-file media summary lines too' );
}

{
    my $runtime = tempdir( CLEANUP => 1 );
    my $home = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-bootstrap-session';
    my $runtime_dir = File::Spec->catdir( $home, '.telegram-codex', 'skills' );
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($runtime_dir);
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-31-00-$session_id.jsonl" );
    _write(
        $session_file,
        encode_json(
            {
                timestamp => '2026-05-22T18:31:01Z',
                type      => 'response_item',
                payload   => {
                    type    => 'message',
                    role    => 'user',
                    content => [ { type => 'input_text', text => 'Bootstrap only' } ],
                },
            }
        ) . "\n",
    );
    _write( File::Spec->catfile( $runtime_dir, 'pairing.json' ), encode_json( { paired_chat_id => 398296603 } ) );
    _write( File::Spec->catfile( $runtime_dir, 'codex.session' ), "$session_id\n" );
    my $manager = new_manager(
        cwd  => $runtime,
        home => $home,
        env  => { TELEGRAM_CODEX_SESSION_ID => 'skills' },
    );
    my %state;
    my $paths = $manager->listener_paths_for_session('skills');
    is( $manager->process_tui_live_outbound_transcript( 'skills', $paths, \%state ), 0, 'process_tui_live_outbound_transcript primes the cursor and returns without replaying old transcript rows when no cursor exists yet' );
    is( $manager->read_text_file( $paths->{transcript_cursor_file} ), (-s $session_file) . "\n", 'process_tui_live_outbound_transcript stores the transcript EOF cursor on first bootstrap' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $cwd = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-outbound-on-error';
    my $runtime_dir = File::Spec->catdir( $home, '.telegram-codex', 'skills' );
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($runtime_dir);
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-31-00-$session_id.jsonl" );
    _write(
        $session_file,
        join(
            "\n",
            encode_json(
                {
                    timestamp => '2026-05-22T18:31:01Z',
                    type      => 'response_item',
                    payload   => {
                        type    => 'message',
                        role    => 'user',
                        content => [ { type => 'input_text', text => 'Please continue' } ],
                    },
                }
            ),
            encode_json(
                {
                    timestamp => '2026-05-22T18:31:02Z',
                    type      => 'response_item',
                    payload   => {
                        type    => 'message',
                        role    => 'assistant',
                        phase   => 'final_answer',
                        content => [ { type => 'output_text', text => 'Finished.' } ],
                    },
                }
            ),
            q{},
        ),
    );
    _write( File::Spec->catfile( $runtime_dir, 'pairing.json' ), encode_json( { paired_chat_id => 398296603 } ) );
    _write( File::Spec->catfile( $runtime_dir, 'codex.session' ), "$session_id\n" );
    _write( File::Spec->catfile( $runtime_dir, 'transcript.cursor' ), "0\n" );
    my @post_calls;
    my $manager = new_manager(
        cwd  => $cwd,
        home => $home,
        env  => { TELEGRAM_CODEX_SESSION_ID => 'skills' },
        post_runner => sub {
            my ( $method, $params ) = @_;
            push @post_calls, [ $method, $params ];
            die "Telegram POST failed for sendMessage: 500 Verbose kickoff rejected\n"
              if $method eq 'sendMessage' && ( $params->{text} || q{} ) =~ /Codex verbose/;
            return {
                ok     => JSON::XS::true,
                result => {
                    message_id => 800 + scalar @post_calls,
                    chat       => { id => $params->{chat_id} },
                },
            };
        },
    );
    my %state;
    my @progress_errors;
    my $paths = $manager->listener_paths_for_session('skills');
    is( $manager->process_tui_live_outbound_transcript( 'skills', $paths, \%state, progress_errors => \@progress_errors ), 2, 'process_tui_live_outbound_transcript still consumes transcript rows when the initial verbose kickoff fails' );
    is( $post_calls[0][0], 'sendChatAction', 'process_tui_live_outbound_transcript still attempts typing before the reporter error path' );
    is( $post_calls[1][0], 'sendMessage', 'process_tui_live_outbound_transcript attempts the verbose kickoff message before the error callback path' );
    like( $progress_errors[0]{error}, qr/Verbose kickoff rejected/, 'process_tui_live_outbound_transcript captures the verbose kickoff failure through the on_error callback' );
    is( $post_calls[-1][1]{text}, 'Finished.', 'process_tui_live_outbound_transcript still delivers the final assistant reply after the verbose kickoff failure' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $cwd = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-pane-no-user';
    my $runtime_dir = File::Spec->catdir( $home, '.telegram-codex', 'skills' );
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($runtime_dir);
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-31-00-$session_id.jsonl" );
    _write( $session_file, q{} );
    my $pauses = 0;
    my $manager = new_manager(
        cwd  => $cwd,
        home => $home,
        env  => { TELEGRAM_CODEX_SESSION_ID => 'skills' },
        tmux_send_runner => sub { return 1; },
        sleep_runner     => sub { $pauses++; return 1; },
    );
    my $error = eval {
        $manager->run_codex_session_live_pane(
            $session_id,
            '%77',
            { text => 'Never shows up' },
        );
        return q{};
    };
    $error = $@ if !$error;
    like( $error, qr/never recorded the injected Telegram turn/, 'run_codex_session_live_pane fails fast when the live pane never records the injected Telegram turn' );
    is( $pauses, 14, 'run_codex_session_live_pane exits after the fast-fail user-detection window instead of waiting for the full timeout' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $cwd = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-pane-no-final';
    my $runtime_dir = File::Spec->catdir( $home, '.telegram-codex', 'skills' );
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($runtime_dir);
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-31-00-$session_id.jsonl" );
    _write( $session_file, q{} );
    my $pauses = 0;
    my $manager = new_manager(
        cwd  => $cwd,
        home => $home,
        env  => { TELEGRAM_CODEX_SESSION_ID => 'skills' },
        tmux_send_runner => sub {
            _write(
                $session_file,
                join(
                    "\n",
                    encode_json(
                        {
                            timestamp => '2026-05-22T18:31:01Z',
                            type      => 'response_item',
                            payload   => {
                                type    => 'message',
                                role    => 'user',
                                content => [ { type => 'input_text', text => 'No final answer yet' } ],
                            },
                        }
                    ),
                    q{},
                )
            );
            return 1;
        },
        sleep_runner     => sub { $pauses++; return 1; },
    );
    my $error = eval {
        $manager->run_codex_session_live_pane(
            $session_id,
            '%77',
            {
                text       => 'No final answer yet',
                chat       => { id => 398296603 },
                message_id => 95,
            },
        );
        return q{};
    };
    $error = $@ if !$error;
    like( $error, qr/Timed out waiting for the live Codex pane to finish the Telegram turn/, 'run_codex_session_live_pane times out when the injected user turn appears but no final assistant answer follows' );
    is( $pauses, 600, 'run_codex_session_live_pane waits through the full live-pane window when the user turn appears but no final assistant answer arrives' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $cwd = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-pane-progress-error';
    my $runtime_dir = File::Spec->catdir( $home, '.telegram-codex', 'skills' );
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($runtime_dir);
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-31-00-$session_id.jsonl" );
    my $prompt = "Check progress callback failure";
    _write( $session_file, q{} );
    my $manager = new_manager(
        cwd  => $cwd,
        home => $home,
        env  => {
            TELEGRAM_CODEX_SESSION_ID => 'skills',
            TELEGRAM_CODEX_AUDIT      => '1',
        },
        tmux_send_runner => sub {
            _write(
                $session_file,
                join(
                    "\n",
                    encode_json(
                        {
                            timestamp => '2026-05-22T18:31:01Z',
                            type      => 'response_item',
                            payload   => {
                                type    => 'message',
                                role    => 'user',
                                content => [ { type => 'input_text', text => $prompt } ],
                            },
                        }
                    ),
                    encode_json(
                        {
                            timestamp => '2026-05-22T18:31:02Z',
                            type      => 'response_item',
                            payload   => {
                                type    => 'message',
                                role    => 'assistant',
                                phase   => 'commentary',
                                content => [ { type => 'output_text', text => 'This commentary will fail' } ],
                            },
                        }
                    ),
                    encode_json(
                        {
                            timestamp => '2026-05-22T18:31:03Z',
                            type      => 'response_item',
                            payload   => {
                                type    => 'message',
                                role    => 'assistant',
                                phase   => 'final_answer',
                                content => [ { type => 'output_text', text => 'Still finished.' } ],
                            },
                        }
                    ),
                    q{},
                ),
            );
            return 1;
        },
    );
    my $reply = $manager->run_codex_session_live_pane(
        $session_id,
        '%118',
        { text => $prompt },
        on_progress => sub { die "progress callback blew up\n" },
    );
    is( $reply, 'Still finished.', 'run_codex_session_live_pane still returns the final answer after a progress callback failure' );
    my $audit = $manager->read_text_file( $manager->listener_paths->{audit_file} );
    like( $audit, qr/codex\.live_pane\.progress_callback_failed/, 'run_codex_session_live_pane audits the progress callback failure' );
    like( $audit, qr/progress callback blew up/, 'run_codex_session_live_pane preserves the progress callback failure detail' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $cwd = tempdir( CLEANUP => 1 );
    my $session_id = '019e-live-pane-timeout';
    my $runtime_dir = File::Spec->catdir( $home, '.telegram-codex', 'skills' );
    my $session_dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '05', '22' );
    make_path($runtime_dir);
    make_path($session_dir);
    my $session_file = File::Spec->catfile( $session_dir, "rollout-2026-05-22T18-31-00-$session_id.jsonl" );
    my $prompt = "Wait forever";
    _write( $session_file, q{} );
    my $pauses = 0;
    my $manager = new_manager(
        cwd  => $cwd,
        home => $home,
        env  => { TELEGRAM_CODEX_SESSION_ID => 'skills' },
        tmux_send_runner => sub {
            _write(
                $session_file,
                encode_json(
                    {
                        timestamp => '2026-05-22T18:31:01Z',
                        type      => 'response_item',
                        payload   => {
                            type    => 'message',
                            role    => 'user',
                            content => [ { type => 'input_text', text => $prompt } ],
                        },
                    }
                ) . "\n",
            );
            return 1;
        },
        sleep_runner => sub { $pauses++; return 1; },
    );
    my $error = eval {
        $manager->run_codex_session_live_pane(
            $session_id,
            '%118',
            { text => $prompt },
        );
        return q{};
    };
    $error = $@ if !$error;
    like( $error, qr/Timed out waiting for the live Codex pane to finish the Telegram turn/, 'run_codex_session_live_pane fails explicitly when no final answer arrives from the live transcript' );
    is( $pauses, 600, 'run_codex_session_live_pane executes the live-pane wait loop until timeout when no final answer arrives' );
}

{
    my $manager = new_manager;
    ok(
        $manager->codex_live_pane_user_event_matches_prompt(
            { text => 'Test', caption => q{} },
            'Test',
            "  Test  \n",
        ),
        'codex_live_pane_user_event_matches_prompt tolerates normalized whitespace differences',
    );
    ok(
        $manager->codex_live_pane_user_event_matches_prompt(
            { text => 'Test', caption => q{} },
            'Test',
            "[Telegram chat 398296603 message 2355]\nTest",
        ),
        'codex_live_pane_user_event_matches_prompt accepts transcript rows that wrap the Telegram text',
    );
    ok(
        $manager->codex_live_pane_user_event_matches_prompt(
            { text => q{}, caption => 'Picture note' },
            "[caption] Picture note",
            "Some transcript preface\n[caption] Picture note",
        ),
        'codex_live_pane_user_event_matches_prompt accepts caption matches when the text body is empty',
    );
    ok(
        !$manager->codex_live_pane_user_event_matches_prompt(
            { text => 'Test', caption => 'Picture note' },
            "Test\n[caption] Picture note",
            'Completely unrelated transcript row',
        ),
        'codex_live_pane_user_event_matches_prompt rejects unrelated transcript rows',
    );
}

sub _write {
    my ( $file, $content ) = @_;
    open my $fh, '>', $file or die "Unable to write $file: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $file: $!";
}

done_testing;
