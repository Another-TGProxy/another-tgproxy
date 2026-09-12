// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    [GtkTemplate (ui = "/space/ampernic/AnotherTGProxy/ui/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Adw.Banner conn_banner;
        [GtkChild] private unowned Adw.Banner err_banner;
        [GtkChild] private unowned Adw.Banner update_banner;
        [GtkChild] private unowned Adw.Banner badhs_banner;
        [GtkChild] private unowned HomeView home_view;
        [GtkChild] private unowned SettingsView settings_view;
        [GtkChild] private unowned LogView log_view;

        private Config cfg;
        private DaemonClient client;
        private ServiceController service;
        private string error_detail = "";

        public Window (Gtk.Application app) {
            Object (application: app);
        }

        construct {
            this.title = Build.APP_NAME;
            // Development builds get libadwaita's striped "devel" header (and the
            // .Devel icon/name from the build profile) so they're unmistakable.
            // Betas wear the striped header too: they carry the release app-id so
            // channel switching updates in place, and without the stripe there is
            // nothing on screen telling a test build from the stable one.
            if (Build.IS_DEVEL || Build.IS_PRERELEASE)
                this.add_css_class ("devel");
            cfg = Config.load ();
            service = new ServiceController (cfg);
            client = new DaemonClient ();

            var act_about = new SimpleAction ("about", null);
            act_about.activate.connect (show_about);
            add_action (act_about);
            var act_quit = new SimpleAction ("quit", null);
            act_quit.activate.connect (() => {
#if ANDROID
                // g_application_quit ends the GTK loop while the activity is still
                // resumed, so it never finishes its lifecycle transition ("top
                // resumed state loss timeout") and the START_STICKY service respawns
                // the process. Go through the Android lifecycle instead.
                var s = get_surface ();
                if (s != null)
                    Station.android_quit (s);
                else
                    application.quit ();
#else
                application.quit ();
#endif
            });
            add_action (act_quit);

            home_view.bind (client, service);
            settings_view.bind (cfg, client, service);
            log_view.start ();
            home_view.toast.connect ((m) => { toast (m); });
            settings_view.toast.connect ((m) => { toast (m); });
            settings_view.setup_requested.connect (() => run_setup (true));

            conn_banner.button_clicked.connect (() => service.start ());
            err_banner.button_clicked.connect (open_error_details);
            badhs_banner.button_clicked.connect (() => {
                if (badhs_link == "") return;
                get_clipboard ().set_text (badhs_link);
                toast (_("Link copied"));
            });
            client.connection_changed.connect (on_connection);
            client.status_changed.connect (on_status);
            service.failed.connect (present_error);
            client.start ();

            // Route this (GUI) process's GLib output to proxy.log so the update
            // check below is visible in the in-app log. No-op on Android, where the
            // in-process EngineHost already set the logger up.
            Logging.attach (cfg);

            // Held back until the first-run wizard is done: an update dialog
            // popping over it would bury the setup the user was in the middle of.
            if (cfg.setup_done)
                start_update_check ();
        }

        private void start_update_check () {
            var u = ensure_updater ();
            if (u != null)
                u.check ();
        }

        // Build the updater for a newer GitHub release. Where a repository installs
        // the app (native and Flatpak Linux) the release is only announced — see
        // Platform.updates_installable. Creating it does not check: the wizard drives
        // its own check on the update step, and the window checks once it's done.
        public Station.Updates? ensure_updater () {
            if (updater != null) return updater;
            if (cfg.check_updates) {
                // GitHub releases; downloads are verified against the SHA256SUMS
                // release asset (libstation resolves the asset URL + checks SHA-256).
                var schema = new Station.ReleaseSchema.github ();
                schema.set_checksums_asset ("SHA256SUMS");
                // Release builds require a minisign signature of the checksums
                // (verified against this baked-in public key, so a compromised
                // release host cannot serve a malicious update). Dev builds verify
                // hashes only, so they can still update to unsigned test releases.
                if (!Build.IS_DEVEL) {
                    schema.set_signature_asset ("SHA256SUMS.minisig");
                    schema.set_public_key (
                        "RWRPM5OxKHSDb1FxBh6td77H5v3omk9CQZpdvGhMF/OwbIfJkf3rh/02");
                }
                updater = new Station.Updates.with_schema (schema,
                    "Another-TGProxy/another-tgproxy", Build.VERSION);
                // Channels this build offers; the prerelease keywords each accepts.
                updater.add_channel ("stable", null);
                updater.add_channel ("beta", { "beta", "rc", "alpha" });
                // Empty config = track beta on a prerelease build, stable otherwise.
                var ch = cfg.update_channel;
                if (ch == "") ch = Build.VERSION.contains ("-") ? "beta" : "stable";
                updater.set_channel (ch);
                // Show only the "What's new" block of the release notes, in the
                // running language: the heading is gettext-translated, so a RU build
                // asks for "Что нового" and gets that section of a bilingual body.
                updater.set_notes_section (_("What's new"));
                updater.available.connect (on_update_available);
                updater.download_progress.connect (on_dl_progress);
                updater.downloaded.connect (on_downloaded);
                updater.download_failed.connect (on_dl_failed);
                update_banner.button_clicked.connect (() => show_update_dialog ());
            }
            return updater;
        }

        // Run the first-run wizard, once. Called after the window is on screen so
        // the dialog has something to attach to.
        private bool setup_active = false;
        // Set once the wizard has had its say about updates this session.
        private bool update_dialog_suppressed = false;

        public void maybe_run_setup () {
            if (cfg.setup_done) return;
            run_setup (false);
        }

        public void run_setup (bool rerun) {
            if (setup_active) return;
            setup_active = true;
            var wizard = new SetupWizard ();
            wizard.toast.connect ((m) => { toast (m); });
            // Hands its update step our updater, and hands the install back to us.
            // The download runs in the wizard's own step: popping the update dialog
            // over it would ask a second time what the step has just asked.
            wizard.update_requested.connect (() => {
                // Whatever the closed dialog left behind is not ours to drive.
                dl_bar = null;
                dl_btn = null;
                dl_wizard = wizard;
                start_download ();
                if (downloading) wizard.download_started ();
            });
            wizard.bind (cfg, client, service, ensure_updater (), rerun);
            // The wizard is modal and refuses to be dismissed, so closing the
            // window has to tear it down explicitly or the window can't close.
            ulong close_id = 0;
            close_id = this.close_request.connect (() => {
                wizard.release ();
                return false;
            });
            // Whatever the outcome — finished or quit — the update check is free
            // to run once the wizard is out of the way.
            wizard.closed.connect (() => {
                this.disconnect (close_id);
                if (dl_wizard == wizard) dl_wizard = null;
                setup_active = false;
                update_dialog_suppressed = true;
                start_update_check ();
            });
            wizard.present (this);
        }

        private Station.Updates? updater = null;
        private string update_url = "";
        private string update_version = "";
        private string update_notes = "";
        private Adw.Dialog? update_dialog = null;
        private Gtk.ProgressBar? dl_bar = null;
        private Gtk.Button? dl_btn = null;
        private bool downloading = false;
        // Set while the wizard, not the update dialog, is showing the progress.
        private SetupWizard? dl_wizard = null;

        private void on_update_available (string version, string url, string notes) {
            // A version the user turned down stays turned down — no banner, no dialog.
            if (version == cfg.skipped_version)
                return;
            update_url = url;
            update_version = version;
            update_notes = notes;
            update_banner.title = _("Update available: %s").printf (version);
            update_banner.revealed = true;
            // Don't pop the dialog over the wizard, nor the moment it closes: the
            // wizard has its own update step, and repeating the offer right after
            // the user has just dealt with it is nagging. The banner stays, so the
            // offer is one click away whenever they want it.
            if (!setup_active && !update_dialog_suppressed)
                show_update_dialog ();
        }

        // A dialog with the release notes, a progress bar and Later/Download.
        // Reachable again via the banner button after it's dismissed.
        private void show_update_dialog () {
            if (update_url == "")
                return;
            var dlg = new Adw.Dialog () {
                title = _("Update available: %s").printf (update_version),
                content_width = 480
            };
            var tv = new Adw.ToolbarView ();
            tv.add_top_bar (new Adw.HeaderBar ());

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_top = 12, margin_bottom = 12, margin_start = 12, margin_end = 12
            };
            if (update_notes != "") {
                // Release notes are Markdown, rendered as widgets (labels + grids for
                // tables) so they stay readable on any width. Not selectable (no text
                // copying); the scroller sizes to the notes (short ones show in full,
                // long ones scroll) rather than a fixed, clipping height.
                box.append (new Gtk.ScrolledWindow () {
                    hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true,
                    propagate_natural_height = true, max_content_height = 360,
                    child = Markdown.render (update_notes)
                });
            }
            dl_bar = new Gtk.ProgressBar () { show_text = true, visible = false };
            box.append (dl_bar);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { halign = Gtk.Align.END };
            // "Later" means ask again; this one means never for this release.
            var skip = new Gtk.Button.with_label (_("Skip this version"));
            skip.add_css_class ("flat");
            skip.clicked.connect (() => {
                cfg.skipped_version = update_version;
                cfg.save ();
                update_banner.revealed = false;
                dlg.close ();
            });
            var later = new Gtk.Button.with_label (_("Later"));
            later.clicked.connect (() => dlg.close ());
            // Nothing to install where a repository owns the app: the offer is the
            // release page, and updating stays the repository's job.
            bool installable = Platform.get_default ().updates_installable ();
            dl_btn = new Gtk.Button.with_label (installable ? _("Download") : _("Release page"));
            dl_btn.add_css_class ("suggested-action");
            dl_btn.clicked.connect (() => {
                if (installable) {
                    start_download ();
                } else {
                    open_external_uri (this, update_url);
                    dlg.close ();
                }
            });
            actions.append (skip);
            actions.append (later);
            actions.append (dl_btn);
            box.append (actions);

            tv.content = box;
            dlg.child = tv;
            update_dialog = dlg;
            dlg.present (this);
        }

        // The release asset this delivery installs (deterministic from the tag and
        // our naming scheme) and where to stage it.
        private string asset_filename () {
            switch (Platform.get_default ().update_kind ()) {
            case UpdateKind.WINDOWS_SETUP:
                return "AnotherTGProxy-%s-windows-x86_64-setup.exe".printf (update_version);
            case UpdateKind.ANDROID_APK:
                return "AnotherTGProxy-%s-android-universal.apk".printf (update_version);
            case UpdateKind.MACOS_DMG:
#if DARWIN
                var u = Posix.utsname ();   // the constructor calls uname()
                var arch = (u.machine == "x86_64") ? "x86_64" : "arm64";
#else
                var arch = "arm64";
#endif
                return "AnotherTGProxy-%s-macos-%s.dmg".printf (update_version, arch);
            case UpdateKind.APPIMAGE:
                return "AnotherTGProxy-%s-linux-x86_64.AppImage".printf (update_version);
            default:
                return "";
            }
        }

        private string asset_dest () {
#if ANDROID
            // gdk-android points XDG_DATA_HOME at the app's external files dir
            // (writable, and readable by our own installApk); the cache dir
            // resolves to a bogus $HOME/.cache here.
            var dir = Environment.get_user_data_dir ();
#else
            var dir = Environment.get_tmp_dir ();
            // The AppImage is replaced in place, so stage the download beside it:
            // /tmp is usually a tmpfs, and a move off it is a cross-device copy.
            if (Platform.get_default ().update_kind () == UpdateKind.APPIMAGE) {
                var cur = Environment.get_variable ("APPIMAGE");
                if (cur != null && cur != "") {
                    var beside = Path.get_dirname (cur);
                    if (Posix.access (beside, Posix.W_OK) == 0)
                        dir = beside;
                }
            }
#endif
            return Path.build_filename (dir, asset_filename ());
        }

        private void start_download () {
            if (updater == null || downloading || asset_filename () == "")
                return;
            var dest = asset_dest ();
            // The staging dir (e.g. the app's XDG_DATA_HOME on Android) may not
            // exist yet; g_file_replace won't create it.
            DirUtils.create_with_parents (Path.get_dirname (dest), 0755);
            downloading = true;
            if (dl_btn != null) { dl_btn.sensitive = false; dl_btn.label = _("Downloading…"); }
            if (dl_bar != null) { dl_bar.visible = true; dl_bar.fraction = 0; dl_bar.text = ""; }
            // libstation resolves the asset URL from the available release and
            // verifies its SHA-256 against the SHA256SUMS asset.
            updater.download_checked (asset_filename (), dest);
        }

        private void on_dl_progress (double frac) {
            if (dl_wizard != null)
                dl_wizard.download_progress (frac);
            if (dl_bar == null)
                return;
            if (frac < 0) {
                dl_bar.pulse ();
            } else {
                dl_bar.fraction = frac;
                dl_bar.text = "%d %%".printf ((int) (frac * 100));
            }
        }

        private void on_downloaded (string path) {
            downloading = false;
            if (dl_wizard != null) {
                dl_wizard.download_finished (install_hint (path));
                dl_wizard = null;
            }
            if (update_dialog != null) update_dialog.close ();
            apply_update (path);
        }

        private void on_dl_failed (string reason) {
            downloading = false;
            if (dl_wizard != null) {
                // The wizard says it in its own step, with its own toast.
                dl_wizard.download_failed (reason);
                dl_wizard = null;
                return;
            }
            if (dl_btn != null) { dl_btn.sensitive = true; dl_btn.label = _("Download"); }
            if (dl_bar != null) dl_bar.visible = false;
            toast (_("Download failed: %s").printf (reason));
        }

        // Hand the downloaded asset to the platform: run the installer (Windows),
        // the system package installer (Android), open the disk image (macOS) or
        // swap the AppImage in place and relaunch.
        private void apply_update (string path) {
            switch (Platform.get_default ().update_kind ()) {
            case UpdateKind.WINDOWS_SETUP:
                try {
                    Process.spawn_async (null, { path }, null,
                        SpawnFlags.DO_NOT_REAP_CHILD, null, null);
                } catch (Error e) {
                    toast (_("Could not start installer: %s").printf (e.message));
                    return;
                }
                application.quit ();
                break;
            case UpdateKind.ANDROID_APK:
#if ANDROID
                var s = get_surface ();
                if (s != null)
                    Station.android_install_apk (s,
                        "space.ampernic.anothertgproxy.ProxyApplication", path);
#endif
                break;
            case UpdateKind.MACOS_DMG:
                try { Station.open_uri ("file://" + path); }
                catch (Error e) { toast (_("Could not open the disk image: %s").printf (e.message)); }
                break;
            case UpdateKind.APPIMAGE:
                // Replace the running image and relaunch the new one.
                var cur = Environment.get_variable ("APPIMAGE");
                if (cur == null || cur == "") {
                    try { Station.open_uri ("file://" + path); } catch (Error e) {}
                    return;
                }
                // GIO falls back to copy+delete when the two are on different
                // filesystems, which rename(2) cannot do.
                try {
                    File.new_for_path (path).move (File.new_for_path (cur),
                                                   FileCopyFlags.OVERWRITE, null, null);
                } catch (Error e) {
                    toast (_("Could not replace the AppImage: %s").printf (e.message));
                    return;
                }
                FileUtils.chmod (cur, 0755);
                try {
                    Process.spawn_async (null, { cur }, null,
                        SpawnFlags.DO_NOT_REAP_CHILD, null, null);
                } catch (Error e) { toast (e.message); return; }
                application.quit ();
                break;
            default:
                break;
            }
        }

        // What actually happens to the file, said in the wizard's own step. The
        // two kinds that restart into the installer never get read.
        private string install_hint (string path) {
            switch (Platform.get_default ().update_kind ()) {
            case UpdateKind.ANDROID_APK:
                return _("Confirm the installation in the system installer. The app restarts on the new version.");
            case UpdateKind.MACOS_DMG:
                return _("The disk image is open: drag the app into Applications, replacing the old one, then start it again.");
            case UpdateKind.WINDOWS_SETUP:
                return _("The installer is starting. The app closes while it runs.");
            case UpdateKind.APPIMAGE:
                return _("The image is being replaced and the app restarts on the new version.");
            default:
                return _("The file is at %s.").printf (path);
            }
        }

        // On macOS/Windows the app lives on in the tray after the window is
        // destroyed; stop this window's control client so its reconnect loop and
        // socket don't linger until finalization.
        public override void dispose () {
            if (client != null) client.stop ();
            base.dispose ();
        }

        private void toast (string msg) {
            toast_overlay.add_toast (new Adw.Toast (msg) { timeout = 2 });
        }

        private void on_connection (bool connected) {
            conn_banner.revealed = !connected;
        }

        private void on_status (Status s) {
            if (s.error != "")
                present_error (s.error);
            else
                err_banner.revealed = false;
            check_bad_handshakes (s);
        }

        // Refusals only mean something while they keep coming: a handful is a
        // client that has just been re-pointed, a steady stream is one still
        // configured with a secret this proxy no longer accepts.
        private const int64 BADHS_WARN_RATE = 20;
        private int64 badhs_seen = -1;
        private string badhs_link = "";

        private void check_bad_handshakes (Status s) {
            int64 prev = badhs_seen;
            badhs_seen = s.bad_handshakes;
            if (prev < 0 || s.bad_handshakes < prev) // first sample, or daemon restarted
                return;
            if (s.bad_handshakes - prev < BADHS_WARN_RATE) {
                badhs_banner.revealed = false;
                return;
            }
            badhs_link = (s.secret.length == 32)
                ? proxy_link (s.host, s.port, s.secret) : "";
            badhs_banner.button_label = (badhs_link != "") ? _("Copy link") : "";
            badhs_banner.title =
                _("Another client keeps connecting with an outdated secret. Re-add the proxy there.");
            badhs_banner.revealed = true;
        }

        // Show errors briefly in the banner; the full text (which can be long or
        // multi-line, e.g. from the engine) stays a click away in a dialog.
        private void present_error (string msg) {
            error_detail = msg.strip ();
            err_banner.title = error_summary (msg);
            err_banner.button_label = (error_detail != err_banner.title) ? _("Details") : "";
            err_banner.revealed = true;
        }

        private void open_error_details () {
            if (error_detail == "")
                return;
            var label = new Gtk.Label (error_detail) {
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                selectable = true,
                xalign = 0,
                yalign = 0
            };
            label.add_css_class ("monospace");
            var scroller = new Gtk.ScrolledWindow () {
                child = label,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                propagate_natural_height = true,
                max_content_height = 360,
                width_request = 320
            };
            var dialog = new Adw.AlertDialog (_("Error details"), null) {
                extra_child = scroller
            };
            dialog.add_response ("close", _("Close"));
            dialog.present (this);
        }

        private void show_about () {
            var about = new Adw.AboutDialog () {
                application_name = Build.APP_NAME,
                application_icon = Build.APP_ID_RELEVANT,
                developer_name = "Ampernic",
                version = Build.VERSION,
                comments = _("An MTProto ↔ WebSocket proxy for Telegram."),
                license_type = Gtk.License.GPL_3_0,
                website = Build.HOMEPAGE,
                issue_url = Build.BUGTRACKER,
                translator_credits = _("translator-credits")
            };
            about.add_link (_("Support channel"), SUPPORT_CHANNEL);
            about.activate_link.connect ((uri) => {
                open_external_uri (this, uri);
                return true;
            });
            about.present (this);
        }
    }
}
