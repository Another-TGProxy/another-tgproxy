// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    [GtkTemplate (ui = "/space/ampernic/AnotherTGProxy/ui/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Adw.Banner conn_banner;
        [GtkChild] private unowned Adw.Banner err_banner;
        [GtkChild] private unowned Adw.Banner update_banner;
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
            if (Build.IS_DEVEL)
                this.add_css_class ("devel");
            cfg = Config.load ();
            service = new ServiceController (cfg);
            client = new DaemonClient ();

            var act_about = new SimpleAction ("about", null);
            act_about.activate.connect (show_about);
            add_action (act_about);
            var act_quit = new SimpleAction ("quit", null);
            act_quit.activate.connect (() => application.quit ());
            add_action (act_quit);

            home_view.bind (client, service);
            settings_view.bind (cfg, client, service);
            log_view.start ();
            home_view.toast.connect ((m) => { toast (m); });
            settings_view.toast.connect ((m) => { toast (m); });

            conn_banner.button_clicked.connect (() => service.start ());
            err_banner.button_clicked.connect (open_error_details);
            client.connection_changed.connect (on_connection);
            client.status_changed.connect (on_status);
            service.failed.connect (present_error);
            client.start ();

            // Route this (GUI) process's GLib output to proxy.log so the update
            // check below is visible in the in-app log. No-op on Android, where the
            // in-process EngineHost already set the logger up.
            Logging.attach (cfg);

            // Notify about a newer GitHub release where no repo manages updates
            // (Windows/macOS/Android/AppImage). Native/Flatpak Linux uses its repo.
            if (cfg.check_updates && Platform.get_default ().updates_relevant ()) {
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
                updater.check ();
            }
        }

        private Station.Updates? updater = null;
        private string update_url = "";
        private string update_version = "";
        private string update_notes = "";
        private Adw.Dialog? update_dialog = null;
        private Gtk.ProgressBar? dl_bar = null;
        private Gtk.Button? dl_btn = null;
        private bool downloading = false;

        private void on_update_available (string version, string url, string notes) {
            update_url = url;
            update_version = version;
            update_notes = notes;
            update_banner.title = _("Update available: %s").printf (version);
            update_banner.revealed = true;
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
                // Release notes are Markdown; render them. Not selectable (no text
                // copying), and the scroller sizes to the notes (short ones show in
                // full, long ones scroll) rather than a fixed, clipping height.
                var label = new Gtk.Label (Markdown.to_pango (update_notes)) {
                    use_markup = true, wrap = true, xalign = 0, yalign = 0, selectable = false,
                    // Leave room for the overlay scrollbar so it doesn't sit on the text.
                    margin_end = 12
                };
                box.append (new Gtk.ScrolledWindow () {
                    hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true,
                    propagate_natural_height = true, max_content_height = 360, child = label
                });
            }
            dl_bar = new Gtk.ProgressBar () { show_text = true, visible = false };
            box.append (dl_bar);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { halign = Gtk.Align.END };
            var later = new Gtk.Button.with_label (_("Later"));
            later.clicked.connect (() => dlg.close ());
            dl_btn = new Gtk.Button.with_label (_("Download"));
            dl_btn.add_css_class ("suggested-action");
            dl_btn.clicked.connect (() => start_download ());
            actions.append (later);
            actions.append (dl_btn);
            box.append (actions);

            tv.content = box;
            dlg.child = tv;
            update_dialog = dlg;
            dlg.present (this);
        }

        // The release asset for this platform (deterministic from the tag and our
        // naming scheme) and where to stage it.
        private string asset_filename () {
#if WINDOWS
            return "AnotherTGProxy-%s-windows-x86_64-setup.exe".printf (update_version);
#elif ANDROID
            return "AnotherTGProxy-%s-android-universal.apk".printf (update_version);
#elif DARWIN
            var u = Posix.utsname ();   // the constructor calls uname()
            var arch = (u.machine == "x86_64") ? "x86_64" : "arm64";
            return "AnotherTGProxy-%s-macos-%s.dmg".printf (update_version, arch);
#else
            return "AnotherTGProxy-%s-linux-x86_64.AppImage".printf (update_version);
#endif
        }

        private string asset_dest () {
#if ANDROID
            // gdk-android points XDG_DATA_HOME at the app's external files dir
            // (writable, and readable by our own installApk); the cache dir
            // resolves to a bogus $HOME/.cache here.
            var dir = Environment.get_user_data_dir ();
#else
            var dir = Environment.get_tmp_dir ();
#endif
            return Path.build_filename (dir, asset_filename ());
        }

        private void start_download () {
            if (updater == null || downloading)
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
            if (update_dialog != null) update_dialog.close ();
            apply_update (path);
        }

        private void on_dl_failed (string reason) {
            downloading = false;
            if (dl_btn != null) { dl_btn.sensitive = true; dl_btn.label = _("Download"); }
            if (dl_bar != null) dl_bar.visible = false;
            toast (_("Download failed: %s").printf (reason));
        }

        // Hand the downloaded asset to the platform: run the installer (Windows),
        // the system package installer (Android), open the disk image (macOS) or
        // swap the AppImage in place and relaunch.
        private void apply_update (string path) {
#if WINDOWS
            try {
                Process.spawn_async (null, { path }, null,
                    SpawnFlags.DO_NOT_REAP_CHILD, null, null);
            } catch (Error e) {
                toast (_("Could not start installer: %s").printf (e.message));
                return;
            }
            application.quit ();
#elif ANDROID
            var s = get_surface ();
            if (s != null)
                Station.android_install_apk (s,
                    "space.ampernic.anothertgproxy.ProxyApplication", path);
#elif DARWIN
            try { Station.open_uri ("file://" + path); }
            catch (Error e) { toast (_("Could not open the disk image: %s").printf (e.message)); }
#else
            // AppImage: replace the running image and relaunch the new one.
            var cur = Environment.get_variable ("APPIMAGE");
            if (cur == null || cur == "") {
                try { Station.open_uri ("file://" + path); } catch (Error e) {}
                return;
            }
            if (FileUtils.rename (path, cur) != 0) {
                toast (_("Could not replace the AppImage"));
                return;
            }
            FileUtils.chmod (cur, 0755);
            try {
                Process.spawn_async (null, { cur }, null,
                    SpawnFlags.DO_NOT_REAP_CHILD, null, null);
            } catch (Error e) { toast (e.message); return; }
            application.quit ();
#endif
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
            about.present (this);
        }
    }
}
