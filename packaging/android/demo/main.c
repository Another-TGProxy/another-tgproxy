/* SPDX-License-Identifier: GPL-3.0-or-later
 * Minimal GTK4 + libadwaita app, used to validate the Pixiewood (GTK-on-Android)
 * toolchain end to end on a CI runner before porting the real app. */
#include <adwaita.h>

static void
on_activate (GApplication *app, gpointer user_data)
{
    GtkWidget *win = adw_application_window_new (GTK_APPLICATION (app));
    gtk_window_set_title (GTK_WINDOW (win), "Adwaita Demo");
    gtk_window_set_default_size (GTK_WINDOW (win), 360, 640);

    GtkWidget *box = gtk_box_new (GTK_ORIENTATION_VERTICAL, 12);
    gtk_widget_set_valign (box, GTK_ALIGN_CENTER);
    gtk_box_append (GTK_BOX (box),
                    gtk_label_new ("GTK4 + libadwaita"));
    gtk_box_append (GTK_BOX (box),
                    gtk_label_new ("running on Android"));

    GtkWidget *toolbar = adw_toolbar_view_new ();
    adw_toolbar_view_add_top_bar (ADW_TOOLBAR_VIEW (toolbar), adw_header_bar_new ());
    adw_toolbar_view_set_content (ADW_TOOLBAR_VIEW (toolbar), box);
    adw_application_window_set_content (ADW_APPLICATION_WINDOW (win), toolbar);
    gtk_window_present (GTK_WINDOW (win));
}

int
main (int argc, char **argv, char **envp)
{
    (void) envp;
    AdwApplication *app = adw_application_new ("space.ampernic.AdwDemo",
                                               G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect (app, "activate", G_CALLBACK (on_activate), NULL);
    return g_application_run (G_APPLICATION (app), argc, argv);
}
