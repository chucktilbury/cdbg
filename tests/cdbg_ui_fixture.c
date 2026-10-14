#include <cwhip/Stdlib.h>
#include <gtk/gtk.h>
#include <gtksourceview/gtksource.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static GtkWindow *debugger_window(void) {
    GList *windows = gtk_application_get_windows(
        GTK_APPLICATION(g_application_get_default()));
    for (GList *item = windows; item; item = item->next)
        if (g_strcmp0(gtk_window_get_title(item->data), "cdbg - local GDB prototype") == 0)
            return item->data;
    return NULL;
}

static GtkWidget *find_type(GtkWidget *widget, GType type) {
    if (G_TYPE_CHECK_INSTANCE_TYPE(widget, type)) return widget;
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child;
         child = gtk_widget_get_next_sibling(child)) {
        GtkWidget *found = find_type(child, type);
        if (found) return found;
    }
    return NULL;
}

static GtkTextView *source_view(void) {
    GtkWindow *window = debugger_window();
    GtkWidget *notebook = window ? find_type(GTK_WIDGET(window), GTK_TYPE_NOTEBOOK) : NULL;
    if (!notebook) return NULL;
    GtkWidget *page = gtk_notebook_get_nth_page(GTK_NOTEBOOK(notebook),
        gtk_notebook_get_current_page(GTK_NOTEBOOK(notebook)));
    return page ? GTK_TEXT_VIEW(find_type(page, GTK_TYPE_TEXT_VIEW)) : NULL;
}

static void label_text(GtkWidget *widget, GString *text) {
    if (GTK_IS_LABEL(widget)) g_string_append(text, gtk_label_get_text(GTK_LABEL(widget)));
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child;
         child = gtk_widget_get_next_sibling(child))
        label_text(child, text);
}

bool cdbg_fixture_alert(void *self) {
    (void)self;
    GtkWindow *parent = debugger_window();
    GListModel *windows = gtk_window_get_toplevels();
    bool found = false;
    for (guint i = 0; i < g_list_model_get_n_items(windows); ++i) {
        GtkWindow *window = g_list_model_get_item(windows, i);
        if (window != parent && gtk_window_get_transient_for(window) == parent &&
            gtk_widget_get_visible(GTK_WIDGET(window)) && gtk_window_get_modal(window) &&
            !g_object_get_data(G_OBJECT(window), "cdbg-answered")) {
            GString *text = g_string_new(NULL);
            label_text(GTK_WIDGET(window), text);
            found = strstr(text->str, "Could not load file") != NULL;
            g_string_free(text, TRUE);
            if (found) {
                GtkWidget *button = find_type(GTK_WIDGET(window), GTK_TYPE_BUTTON);
                g_object_set_data(G_OBJECT(window), "cdbg-answered", GINT_TO_POINTER(1));
                G_GNUC_BEGIN_IGNORE_DEPRECATIONS
                if (GTK_IS_DIALOG(window) && button)
                    gtk_dialog_response(GTK_DIALOG(window),
                        gtk_dialog_get_response_for_widget(GTK_DIALOG(window), button));
                else if (button) g_signal_emit_by_name(button, "clicked");
                G_GNUC_END_IGNORE_DEPRECATIONS
            }
        }
        g_object_unref(window);
        if (found) break;
    }
    return found;
}

static bool panes_readonly(GtkWidget *widget) {
    if (GTK_IS_TEXT_VIEW(widget) &&
        (gtk_text_view_get_editable(GTK_TEXT_VIEW(widget)) ||
         !(gtk_text_view_get_input_hints(GTK_TEXT_VIEW(widget)) & GTK_INPUT_HINT_NO_EMOJI)))
        return false;
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child;
         child = gtk_widget_get_next_sibling(child))
        if (!panes_readonly(child)) return false;
    return true;
}

bool cdbg_fixture_panes(void *self) {
    (void)self;
    GtkWindow *window = debugger_window();
    return window && panes_readonly(GTK_WIDGET(window));
}

bool cdbg_fixture_no_emoji(void *self) {
    (void)self;
    GtkTextView *view = source_view();
    if (!view || !gtk_widget_activate_action(GTK_WIDGET(view), "menu.popup", NULL))
        return false;
    GtkWidget *menu = find_type(GTK_WIDGET(view), GTK_TYPE_POPOVER_MENU);
    GString *text = g_string_new(NULL);
    if (menu) label_text(menu, text);
    bool valid = menu && !strstr(text->str, "Emoji") && strstr(text->str, "Copy");
    if (menu) gtk_popover_popdown(GTK_POPOVER(menu));
    g_string_free(text, TRUE);
    return valid;
}

bool cdbg_fixture_centered(void *self) {
    (void)self;
    GtkTextView *view = source_view();
    if (!view || !gtk_widget_get_mapped(GTK_WIDGET(view))) return false;
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(view);
    GtkTextIter cursor;
    gtk_text_buffer_get_iter_at_mark(buffer, &cursor, gtk_text_buffer_get_insert(buffer));
    GdkRectangle line, visible;
    gtk_text_view_get_iter_location(view, &cursor, &line);
    gtk_text_view_get_visible_rect(view, &visible);
    double delta = fabs(line.y + line.height / 2.0 - visible.y - visible.height / 2.0);
    return visible.height > 100 && delta <= 2 * line.height;
}

static int64_t buffer_changes;

static void changed(GtkTextBuffer *buffer, gpointer unused) {
    (void)buffer;
    (void)unused;
    ++buffer_changes;
}

void cdbg_fixture_track(void *self) {
    (void)self;
    GtkTextView *view = source_view();
    if (!view) g_error("Missing source view");
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(view);
    g_signal_connect(buffer, "changed", G_CALLBACK(changed), NULL);
    buffer_changes = 0;
}

int64_t cdbg_fixture_changes(void *self) {
    (void)self;
    return buffer_changes;
}

static GtkWidget *notebook_at(int index) {
    GtkWindow *window = debugger_window();
    if (!window) return NULL;
    GPtrArray *found = g_ptr_array_new();
    GtkWidget *stack[256];
    int depth = 0;
    stack[depth++] = GTK_WIDGET(window);
    /* Breadth-insensitive preorder walk; the source notebook precedes the
     * inspector notebook in the window's Paned. */
    while (depth > 0) {
        GtkWidget *widget = stack[--depth];
        if (GTK_IS_NOTEBOOK(widget)) g_ptr_array_add(found, widget);
        GtkWidget *children[64];
        int count = 0;
        for (GtkWidget *child = gtk_widget_get_last_child(widget); child && count < 64;
             child = gtk_widget_get_prev_sibling(child))
            children[count++] = child;
        for (int i = 0; i < count && depth < 256; ++i) stack[depth++] = children[i];
    }
    GtkWidget *result = index < (int)found->len ? g_ptr_array_index(found, index) : NULL;
    g_ptr_array_free(found, TRUE);
    return result;
}

static char *text_arg(void *text) {
    const char *bytes;
    uint64_t length;
    cwhip_string_bytes(text, &bytes, &length);
    return length ? g_strndup(bytes, length) : g_strdup("");
}

/* Every source and inspector tab is drawn with the bordered tab style. */
bool cdbg_fixture_bordered(void *self) {
    (void)self;
    GtkWidget *source = notebook_at(0), *inspector = notebook_at(1);
    return source && inspector && !notebook_at(2) &&
           gtk_widget_has_css_class(source, "cwhip-file-tabs") &&
           gtk_widget_has_css_class(inspector, "cwhip-file-tabs");
}

static GtkWidget *close_button(GtkWidget *tab) {
    if (!GTK_IS_BOX(tab)) return NULL;
    for (GtkWidget *child = gtk_widget_get_first_child(tab); child;
         child = gtk_widget_get_next_sibling(child))
        if (GTK_IS_BUTTON(child) &&
            g_strcmp0(gtk_button_get_icon_name(GTK_BUTTON(child)), "window-close-symbolic") == 0)
            return child;
    return NULL;
}

static GtkWidget *tab_label(GtkWidget *notebook, int page) {
    return gtk_notebook_get_tab_label(GTK_NOTEBOOK(notebook),
        gtk_notebook_get_nth_page(GTK_NOTEBOOK(notebook), page));
}

int64_t cdbg_fixture_close_buttons(void *self) {
    (void)self;
    GtkWidget *notebook = notebook_at(0);
    int64_t count = 0;
    for (int i = 0; notebook && i < gtk_notebook_get_n_pages(GTK_NOTEBOOK(notebook)); ++i)
        if (close_button(tab_label(notebook, i))) ++count;
    return count;
}

/* Clicks the real close icon on the source tab titled name. */
bool cdbg_fixture_close_tab(void *self, void *name) {
    (void)self;
    char *title = text_arg(name);
    GtkWidget *notebook = notebook_at(0);
    bool clicked = false;
    for (int i = 0; notebook && !clicked && i < gtk_notebook_get_n_pages(GTK_NOTEBOOK(notebook)); ++i) {
        GtkWidget *tab = tab_label(notebook, i);
        GtkWidget *button = close_button(tab);
        GtkWidget *label = GTK_IS_BOX(tab) ? gtk_widget_get_first_child(tab) : NULL;
        if (button && GTK_IS_LABEL(label) &&
            g_strcmp0(gtk_label_get_text(GTK_LABEL(label)), title) == 0) {
            g_signal_emit_by_name(button, "clicked");
            clicked = true;
        }
    }
    g_free(title);
    return clicked;
}

bool cdbg_fixture_source_visible(void *self) {
    (void)self;
    GtkWidget *notebook = notebook_at(0);
    return notebook && gtk_widget_get_visible(notebook) && gtk_widget_get_mapped(notebook) &&
           gtk_notebook_get_n_pages(GTK_NOTEBOOK(notebook)) >= 1 && source_view() &&
           gtk_widget_get_mapped(GTK_WIDGET(source_view()));
}

static GtkWindow *find_window(void) {
    GtkWindow *parent = debugger_window();
    GListModel *windows = gtk_window_get_toplevels();
    GtkWindow *found = NULL;
    for (guint i = 0; !found && i < g_list_model_get_n_items(windows); ++i) {
        GtkWindow *window = g_list_model_get_item(windows, i);
        if (window != parent && gtk_window_get_transient_for(window) == parent &&
            g_strcmp0(gtk_window_get_title(window), "Find") == 0)
            found = window;
        g_object_unref(window);
    }
    return found;
}

bool cdbg_fixture_find_visible(void *self) {
    (void)self;
    GtkWindow *window = find_window();
    return window && gtk_widget_get_visible(GTK_WIDGET(window));
}

static GtkWidget *button_labeled(GtkWidget *widget, const char *label) {
    if (GTK_IS_BUTTON(widget) && g_strcmp0(gtk_button_get_label(GTK_BUTTON(widget)), label) == 0)
        return widget;
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child;
         child = gtk_widget_get_next_sibling(child)) {
        GtkWidget *found = button_labeled(child, label);
        if (found) return found;
    }
    return NULL;
}

bool cdbg_fixture_step(void *self, void *name, bool keyboard) {
    (void)self;
    GtkWindow *window = debugger_window();
    char *label = text_arg(name);
    GtkWidget *button = window ? button_labeled(GTK_WIDGET(window), label) : NULL;
    g_free(label);
    if (!button || !gtk_widget_is_sensitive(button)) return false;
    if (keyboard) {
        gtk_widget_grab_focus(button);
        return gtk_widget_activate(button);
    }
    g_signal_emit_by_name(button, "clicked");
    return true;
}

/* Find dialog layout: one text entry plus Find Next, Find Previous and Close. */
bool cdbg_fixture_find_click(void *self, void *name) {
    (void)self;
    GtkWindow *window = find_window();
    char *label = text_arg(name);
    GtkWidget *button = window ? button_labeled(GTK_WIDGET(window), label) : NULL;
    bool complete = window && find_type(GTK_WIDGET(window), GTK_TYPE_ENTRY) &&
                    button_labeled(GTK_WIDGET(window), "Find Next") &&
                    button_labeled(GTK_WIDGET(window), "Find Previous") &&
                    button_labeled(GTK_WIDGET(window), "Close");
    if (complete && button) g_signal_emit_by_name(button, "clicked");
    g_free(label);
    return complete && button;
}

/* Activates a window shortcut through its real GtkShortcutController action. */
bool cdbg_fixture_shortcut(void *self, void *trigger_text) {
    (void)self;
    GtkWidget *window = GTK_WIDGET(debugger_window());
    char *text = text_arg(trigger_text);
    GtkShortcutTrigger *requested = gtk_shortcut_trigger_parse_string(text);
    g_free(text);
    if (!window || !requested) return false;
    GtkShortcut *match = NULL;
    GListModel *controllers = gtk_widget_observe_controllers(window);
    for (guint i = 0; !match && i < g_list_model_get_n_items(controllers); ++i) {
        GtkEventController *controller = g_list_model_get_item(controllers, i);
        if (GTK_IS_SHORTCUT_CONTROLLER(controller)) {
            GListModel *shortcuts = G_LIST_MODEL(controller);
            for (guint j = 0; !match && j < g_list_model_get_n_items(shortcuts); ++j) {
                GtkShortcut *shortcut = g_list_model_get_item(shortcuts, j);
                if (gtk_shortcut_trigger_equal(gtk_shortcut_get_trigger(shortcut), requested))
                    match = g_object_ref(shortcut);
                g_object_unref(shortcut);
            }
        }
        g_object_unref(controller);
    }
    g_object_unref(controllers);
    g_object_unref(requested);
    if (!match) return false;
    g_object_ref(window);
    bool activated = gtk_shortcut_action_activate(gtk_shortcut_get_action(match),
        GTK_SHORTCUT_ACTION_EXCLUSIVE, window, NULL);
    g_object_unref(window);
    g_object_unref(match);
    return activated;
}

static char *chosen_path;
static guint chooser_attempts;
static gboolean chooser_selected;

static bool chooser_loading(GtkWidget *widget) {
    GdkCursor *cursor = gtk_widget_get_cursor(widget);
    if (cursor && g_strcmp0(gdk_cursor_get_name(cursor), "progress") == 0) return true;
    if (GTK_IS_SPINNER(widget) && gtk_widget_get_mapped(widget) &&
        gtk_spinner_get_spinning(GTK_SPINNER(widget)))
        return true;
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child;
         child = gtk_widget_get_next_sibling(child))
        if (chooser_loading(child)) return true;
    return false;
}

G_GNUC_BEGIN_IGNORE_DEPRECATIONS
/* Mirrors the editor fixture: act only after the chooser stops loading. */
static gboolean accept_chooser(gpointer data) {
    GtkWidget *dialog = data;
    if (++chooser_attempts > 200) g_error("File chooser never selected %s", chosen_path);
    if (chooser_loading(dialog)) return G_SOURCE_CONTINUE;
    GFile *expected = g_file_new_for_path(chosen_path);
    GFile *selected = gtk_file_chooser_get_file(GTK_FILE_CHOOSER(dialog));
    bool ready = selected && g_file_equal(selected, expected);
    if (!ready && !chooser_selected) {
        if (!gtk_file_chooser_set_file(GTK_FILE_CHOOSER(dialog), expected, NULL))
            g_error("File chooser rejected %s", chosen_path);
        chooser_selected = TRUE;
    }
    g_clear_object(&selected);
    g_object_unref(expected);
    if (!ready) return G_SOURCE_CONTINUE;
    gtk_dialog_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
    return G_SOURCE_REMOVE;
}

static gboolean answer_chooser(gpointer unused) {
    (void)unused;
    if (++chooser_attempts > 400) g_error("File chooser never appeared");
    GListModel *windows = gtk_window_get_toplevels();
    for (guint i = 0; i < g_list_model_get_n_items(windows); ++i) {
        GtkWindow *window = g_list_model_get_item(windows, i);
        if (GTK_IS_FILE_CHOOSER(window) && gtk_widget_get_visible(GTK_WIDGET(window)) &&
            !chooser_loading(GTK_WIDGET(window))) {
            char *folder = g_path_get_dirname(chosen_path);
            GFile *file = g_file_new_for_path(folder);
            GFile *current = gtk_file_chooser_get_current_folder(GTK_FILE_CHOOSER(window));
            if ((!current || !g_file_equal(current, file)) &&
                !gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(window), file, NULL))
                g_error("File chooser rejected folder %s", folder);
            g_clear_object(&current);
            g_object_unref(file);
            g_free(folder);
            chooser_attempts = 0;
            chooser_selected = FALSE;
            g_timeout_add_full(G_PRIORITY_DEFAULT, 500, accept_chooser,
                               g_object_ref(window), g_object_unref);
            g_object_unref(window);
            return G_SOURCE_REMOVE;
        }
        g_object_unref(window);
    }
    return G_SOURCE_CONTINUE;
}
G_GNUC_END_IGNORE_DEPRECATIONS

/* Answers the next native file chooser parented to cdbg with path. */
void cdbg_fixture_choose(void *self, void *path) {
    (void)self;
    g_free(chosen_path);
    chosen_path = text_arg(path);
    chooser_attempts = 0;
    g_timeout_add(500, answer_chooser, NULL);
}

bool cdbg_fixture_compact(void *self) {
    (void)self;
    GtkWidget *window = GTK_WIDGET(debugger_window());
    return window && !find_type(window, GTK_TYPE_ENTRY) &&
        !button_labeled(window, "End Session") &&
        !button_labeled(window, "Select Frame") && !button_labeled(window, "Delete ID");
}

static GtkTextView *inspector_view(const char *title);

bool cdbg_fixture_no_break_menus(void *self) {
    (void)self;
    GtkTextView *source = source_view(), *breaks = inspector_view("Breakpoints");
    return source && breaks &&
        !button_labeled(GTK_WIDGET(source), "Add Breakpoint") &&
        !button_labeled(GTK_WIDGET(source), "Delete Breakpoint") &&
        !button_labeled(GTK_WIDGET(breaks), "Delete Breakpoint");
}

static GtkTextView *inspector_view(const char *title) {
    GtkWidget *notebook = notebook_at(1);
    if (!notebook) return NULL;
    for (int i = 0; i < gtk_notebook_get_n_pages(GTK_NOTEBOOK(notebook)); ++i) {
        GtkWidget *page = gtk_notebook_get_nth_page(GTK_NOTEBOOK(notebook), i);
        if (g_strcmp0(gtk_notebook_get_tab_label_text(GTK_NOTEBOOK(notebook), page), title) == 0) {
            gtk_notebook_set_current_page(GTK_NOTEBOOK(notebook), i);
            GtkWidget *view = find_type(page, GTK_TYPE_TEXT_VIEW);
            return view ? GTK_TEXT_VIEW(view) : NULL;
        }
    }
    return NULL;
}

/* The visible popover holding the labelled item; GtkTextView may own other
   (hidden) popovers once text has been selected. */
static GtkWidget *menu_popover(GtkWidget *widget, const char *label) {
    if (GTK_IS_POPOVER(widget) && gtk_widget_get_visible(widget) && button_labeled(widget, label))
        return widget;
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child;
         child = gtk_widget_get_next_sibling(child)) {
        GtkWidget *found = menu_popover(child, label);
        if (found) return found;
    }
    return NULL;
}

/* Drive the real capture-phase click controller at a displayed text line. */
bool cdbg_fixture_line_click(void *self, void *pane, int64_t line, void *action) {
    (void)self;
    char *title = text_arg(pane), *label = text_arg(action);
    GtkTextView *view = *title ? inspector_view(title) : source_view();
    g_free(title);
    if (!view || !gtk_widget_get_mapped(GTK_WIDGET(view))) {
        g_free(label);
        return false;
    }
    GtkTextIter iter;
    gtk_text_buffer_get_iter_at_line(gtk_text_view_get_buffer(view), &iter, line - 1);
    GdkRectangle rect;
    gtk_text_view_get_iter_location(view, &iter, &rect);
    int x, y;
    gtk_text_view_buffer_to_window_coords(view, GTK_TEXT_WINDOW_WIDGET,
        rect.x + 2, rect.y + rect.height / 2, &x, &y);
    GtkTextIter hit;
    gtk_text_view_get_iter_at_location(view, &hit, rect.x + 2, rect.y + rect.height / 2);
    if (gtk_text_iter_get_line(&hit) != line - 1) {
        g_free(label);
        return false;
    }
    guint button = *label ? GDK_BUTTON_SECONDARY : GDK_BUTTON_PRIMARY;
    GtkGesture *match = NULL;
    GListModel *controllers = gtk_widget_observe_controllers(GTK_WIDGET(view));
    for (guint i = 0; !match && i < g_list_model_get_n_items(controllers); ++i) {
        GtkEventController *controller = g_list_model_get_item(controllers, i);
        if (GTK_IS_GESTURE_CLICK(controller) &&
            gtk_event_controller_get_propagation_phase(controller) == GTK_PHASE_CAPTURE &&
            gtk_gesture_single_get_button(GTK_GESTURE_SINGLE(controller)) == button)
            match = GTK_GESTURE(g_object_ref(controller));
        g_object_unref(controller);
    }
    g_object_unref(controllers);
    bool activated = false;
    if (match) {
        g_object_ref(view);
        g_signal_emit_by_name(match, "pressed", 1, (double)x, (double)y);
        if (*label) {
            GtkWidget *popover = menu_popover(GTK_WIDGET(view), label);
            GtkWidget *item = popover ? button_labeled(popover, label) : NULL;
            if (item) {
                g_signal_emit_by_name(item, "clicked");
                activated = true;
            }
        } else activated = true;
        g_object_unref(view);
        g_object_unref(match);
    }
    g_free(label);
    return activated;
}

int64_t cdbg_fixture_marks(void *self, void *filename, int64_t line) {
    (void)self;
    char *name = text_arg(filename);
    GtkWidget *notebook = notebook_at(0);
    int64_t count = 0;
    for (int i = 0; notebook && i < gtk_notebook_get_n_pages(GTK_NOTEBOOK(notebook)); ++i) {
        GtkWidget *tab = tab_label(notebook, i);
        GtkWidget *label = GTK_IS_BOX(tab) ? gtk_widget_get_first_child(tab) : tab;
        if (!GTK_IS_LABEL(label) || g_strcmp0(gtk_label_get_text(GTK_LABEL(label)), name)) continue;
        GtkWidget *page = gtk_notebook_get_nth_page(GTK_NOTEBOOK(notebook), i);
        GtkSourceView *view = GTK_SOURCE_VIEW(find_type(page, GTK_SOURCE_TYPE_VIEW));
        GtkSourceBuffer *buffer = GTK_SOURCE_BUFFER(gtk_text_view_get_buffer(GTK_TEXT_VIEW(view)));
        GSList *marks = gtk_source_buffer_get_source_marks_at_line(buffer, line - 1, NULL);
        for (GSList *item = marks; item; item = item->next) {
            const char *category = gtk_source_mark_get_category(item->data);
            GtkSourceMarkAttributes *style = gtk_source_view_get_mark_attributes(view, category, NULL);
            GdkRGBA background;
            if ((g_strcmp0(category, "breakpoint") == 0 ||
                 g_strcmp0(category, "disabled-breakpoint") == 0) &&
                gtk_source_view_get_show_line_marks(view) && style &&
                gtk_source_mark_attributes_get_background(style, &background) &&
                gtk_source_mark_attributes_get_icon_name(style))
                ++count;
        }

        g_slist_free(marks);
    }
    g_free(name);
    return count;
}

bool cdbg_fixture_disabled(void *self, int64_t line) {
    (void)self;
    GtkTextView *view = source_view();
    if (!view) return false;
    GSList *marks = gtk_source_buffer_get_source_marks_at_line(
        GTK_SOURCE_BUFFER(gtk_text_view_get_buffer(view)), line - 1, "disabled-breakpoint");
    bool found = marks != NULL;
    g_slist_free(marks);
    return found;
}

static GtkWindow *dialog_titled(const char *title) {
    GListModel *windows = gtk_window_get_toplevels();
    GtkWindow *found = NULL;
    for (guint i = 0; !found && i < g_list_model_get_n_items(windows); ++i) {
        GtkWindow *window = g_list_model_get_item(windows, i);
        if (gtk_window_get_transient_for(window) == debugger_window() &&
            g_strcmp0(gtk_window_get_title(window), title) == 0 &&
            gtk_widget_get_visible(GTK_WIDGET(window)))
            found = window;
        g_object_unref(window);
    }
    return found;
}

bool cdbg_fixture_watch(void *self, void *expression, bool accept) {
    (void)self;
    GtkWindow *dialog = dialog_titled("Add Watch");
    GtkWidget *entry = dialog ? find_type(GTK_WIDGET(dialog), GTK_TYPE_ENTRY) : NULL;
    GtkWidget *button = dialog ? button_labeled(GTK_WIDGET(dialog), accept ? "Add" : "Cancel") : NULL;
    if (!entry || !button) return false;
    char *text = text_arg(expression);
    gtk_editable_set_text(GTK_EDITABLE(entry), text);
    g_free(text);
    g_signal_emit_by_name(button, "clicked");
    return !gtk_widget_get_visible(GTK_WIDGET(dialog));
}

/* Drive the real Setup dialog: start < 0 leaves the checkbox alone. Returns
   true when the dialog is hidden after the button click. */
bool cdbg_fixture_setup(void *self, int64_t start, void *arguments, void *action) {
    (void)self;
    GtkWindow *dialog = dialog_titled("Setup");
    GtkWidget *check = dialog ? find_type(GTK_WIDGET(dialog), GTK_TYPE_CHECK_BUTTON) : NULL;
    GtkWidget *entry = dialog ? find_type(GTK_WIDGET(dialog), GTK_TYPE_ENTRY) : NULL;
    char *label = text_arg(action);
    GtkWidget *button = dialog ? button_labeled(GTK_WIDGET(dialog), label) : NULL;
    g_free(label);
    if (!check || !entry || !button) return false;
    if (start >= 0) gtk_check_button_set_active(GTK_CHECK_BUTTON(check), start != 0);
    char *text = text_arg(arguments);
    gtk_editable_set_text(GTK_EDITABLE(entry), text);
    g_free(text);
    g_signal_emit_by_name(button, "clicked");
    return !gtk_widget_get_visible(GTK_WIDGET(dialog));
}

static void clipboard_done(GObject *source, GAsyncResult *result, gpointer data) {
    char **text = data;
    *text = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(source), result, NULL);
    if (!*text) *text = g_strdup("");
}

/* Read the real display clipboard and compare it with the expected text. */
bool cdbg_fixture_clipboard(void *self, void *expected) {
    (void)self;
    char *text = NULL, *want = text_arg(expected);
    GdkClipboard *clipboard = gdk_display_get_clipboard(gdk_display_get_default());
    gdk_clipboard_read_text_async(clipboard, NULL, clipboard_done, &text);
    gint64 deadline = g_get_monotonic_time() + 5 * G_USEC_PER_SEC;
    while (!text && g_get_monotonic_time() < deadline) g_main_context_iteration(NULL, TRUE);
    bool same = text && g_strcmp0(text, want) == 0;
    if (!same) fprintf(stderr, "clipboard '%s' expected '%s'\n", text ? text : "(none)", want);
    g_free(text);
    g_free(want);
    return same;
}
