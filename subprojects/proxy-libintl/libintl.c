/* SPDX-License-Identifier: GPL-3.0-or-later */
/* A real (non-stub) drop-in for proxy-libintl. GLib/GTK on Android otherwise get
 * proxy-libintl built -DSTUB_ONLY, whose gettext is a no-op, so nothing
 * translates. This parses GNU .mo catalogs and selects the language from the
 * environment, exposing the same g_libintl_* symbols proxy-libintl's libintl.h
 * maps gettext/dgettext/... onto, so GLib, GTK and the app pick it up unchanged.
 *
 * Catalogs are looked up at <bound-dir>/<lang>/LC_MESSAGES/<domain>.mo. Plural
 * handling is best-effort (the app uses none); singular lookup is exact. */
#define _GNU_SOURCE
#include "libintl.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MO_MAGIC 0x950412deU

typedef struct {
  char    *data;       /* whole .mo file, kept for the process lifetime */
  uint32_t count;
  uint32_t orig_off;   /* byte offset of the original-strings table */
  uint32_t trans_off;  /* byte offset of the translation table */
  int      swapped;
} Catalog;

typedef struct CatEntry {
  char            *domain;
  Catalog         *cat;   /* NULL: resolved, but no catalog for this language */
  struct CatEntry *next;
} CatEntry;

typedef struct Binding {
  char           *domain;
  char           *dir;
  struct Binding *next;
} Binding;

static Binding  *bindings = NULL;
static CatEntry *catalogs = NULL;
static char     *current_domain = NULL;

static uint32_t
mo_u32 (const Catalog *c, uint32_t off)
{
  uint32_t v;
  memcpy (&v, c->data + off, 4);
  return c->swapped ? __builtin_bswap32 (v) : v;
}

/* Language string, env-priority (LANGUAGE first; no setlocale C-guard — bionic
 * has no usable locale state). LANGUAGE may be a ':'-separated preference list. */
static const char *
env_language (void)
{
  const char *v;
  if ((v = getenv ("LANGUAGE")) && *v) return v;
  if ((v = getenv ("LC_ALL")) && *v) return v;
  if ((v = getenv ("LC_MESSAGES")) && *v) return v;
  if ((v = getenv ("LANG")) && *v) return v;
  return "C";
}

static void
normalise (char *s)
{
  char *p;
  if ((p = strchr (s, '.'))) *p = '\0';   /* drop .codeset  */
  if ((p = strchr (s, '@'))) *p = '\0';   /* drop @modifier */
}

static Catalog *
load_mo (const char *path)
{
  FILE *f = fopen (path, "rb");
  if (!f) return NULL;
  fseek (f, 0, SEEK_END);
  long n = ftell (f);
  fseek (f, 0, SEEK_SET);
  if (n < 28) { fclose (f); return NULL; }
  char *data = malloc ((size_t) n);
  if (!data) { fclose (f); return NULL; }
  if (fread (data, 1, (size_t) n, f) != (size_t) n) { free (data); fclose (f); return NULL; }
  fclose (f);

  uint32_t magic;
  memcpy (&magic, data, 4);
  int swapped;
  if (magic == MO_MAGIC) swapped = 0;
  else if (magic == __builtin_bswap32 (MO_MAGIC)) swapped = 1;
  else { free (data); return NULL; }

  Catalog *c = calloc (1, sizeof *c);
  c->data = data;
  c->swapped = swapped;
  c->count = mo_u32 (c, 8);
  c->orig_off = mo_u32 (c, 12);
  c->trans_off = mo_u32 (c, 16);
  return c;
}

/* Try <dir>/<lang>/LC_MESSAGES/<domain>.mo for each candidate language. */
static Catalog *
open_catalog (const char *domain, const char *dir)
{
  if (!dir) return NULL;
  char langs[256];
  strncpy (langs, env_language (), sizeof langs - 1);
  langs[sizeof langs - 1] = '\0';

  for (char *tok = strtok (langs, ":"); tok; tok = strtok (NULL, ":")) {
    char cand[256];
    strncpy (cand, tok, sizeof cand - 1);
    cand[sizeof cand - 1] = '\0';
    normalise (cand);
    if (!*cand || strcmp (cand, "C") == 0 || strcmp (cand, "POSIX") == 0)
      continue;

    char path[1024];
    snprintf (path, sizeof path, "%s/%s/LC_MESSAGES/%s.mo", dir, cand, domain);
    Catalog *c = load_mo (path);
    if (c) return c;

    char *us = strchr (cand, '_');   /* fall back ll_CC -> ll */
    if (us) {
      *us = '\0';
      snprintf (path, sizeof path, "%s/%s/LC_MESSAGES/%s.mo", dir, cand, domain);
      c = load_mo (path);
      if (c) return c;
    }
  }
  return NULL;
}

static const char *
binding_dir (const char *domain)
{
  for (Binding *b = bindings; b; b = b->next)
    if (strcmp (b->domain, domain) == 0) return b->dir;
  return NULL;
}

static void
forget_catalog (const char *domain)
{
  CatEntry **pp = &catalogs;
  while (*pp) {
    if (strcmp ((*pp)->domain, domain) == 0) {
      CatEntry *e = *pp;
      *pp = e->next;
      if (e->cat) { free (e->cat->data); free (e->cat); }
      free (e->domain);
      free (e);
      return;
    }
    pp = &(*pp)->next;
  }
}

static Catalog *
get_catalog (const char *domain)
{
  for (CatEntry *e = catalogs; e; e = e->next)
    if (strcmp (e->domain, domain) == 0) return e->cat;

  Catalog *c = open_catalog (domain, binding_dir (domain));
  CatEntry *e = calloc (1, sizeof *e);
  e->domain = strdup (domain);
  e->cat = c;
  e->next = catalogs;
  catalogs = e;
  return c;
}

/* Binary search the sorted original table; return the translation or NULL. */
static const char *
catalog_lookup (Catalog *c, const char *msgid)
{
  if (!c || c->count == 0) return NULL;
  int lo = 0, hi = (int) c->count - 1;
  while (lo <= hi) {
    int mid = (lo + hi) / 2;
    uint32_t ooff = mo_u32 (c, c->orig_off + 8 * (uint32_t) mid + 4);
    int cmp = strcmp (msgid, c->data + ooff);
    if (cmp == 0) {
      uint32_t toff = mo_u32 (c, c->trans_off + 8 * (uint32_t) mid + 4);
      return c->data + toff;
    }
    if (cmp < 0) hi = mid - 1;
    else lo = mid + 1;
  }
  return NULL;
}

static const char *
resolve_domain (const char *domain)
{
  if (domain) return domain;
  if (current_domain) return current_domain;
  return "messages";
}

char *
g_libintl_dcgettext (const char *domain, const char *msgid, int category)
{
  (void) category;
  if (!msgid) return NULL;
  const char *t = catalog_lookup (get_catalog (resolve_domain (domain)), msgid);
  return (char *) (t && *t ? t : msgid);
}

char *
g_libintl_dgettext (const char *domain, const char *msgid)
{
  return g_libintl_dcgettext (domain, msgid, LC_MESSAGES);
}

char *
g_libintl_gettext (const char *msgid)
{
  return g_libintl_dcgettext (NULL, msgid, LC_MESSAGES);
}

/* Pick the idx-th NUL-separated form of a translation. */
static const char *
nth_form (const char *s, unsigned long idx)
{
  while (idx-- && *s) s += strlen (s) + 1;
  return s;
}

char *
g_libintl_dcngettext (const char *domain, const char *m1, const char *m2,
                      unsigned long n, int category)
{
  (void) category;
  const char *t = catalog_lookup (get_catalog (resolve_domain (domain)), m1);
  if (t && *t) {
    const char *form = nth_form (t, n == 1 ? 0 : 1);   /* best-effort plural */
    if (form && *form) return (char *) form;
  }
  return (char *) (n == 1 ? m1 : m2);
}

char *
g_libintl_dngettext (const char *domain, const char *m1, const char *m2,
                     unsigned long n)
{
  return g_libintl_dcngettext (domain, m1, m2, n, LC_MESSAGES);
}

char *
g_libintl_ngettext (const char *m1, const char *m2, unsigned long n)
{
  return g_libintl_dcngettext (NULL, m1, m2, n, LC_MESSAGES);
}

char *
g_libintl_textdomain (const char *domain)
{
  if (domain) {
    free (current_domain);
    current_domain = strdup (domain);
  }
  return current_domain ? current_domain : (char *) "messages";
}

char *
g_libintl_bindtextdomain (const char *domain, const char *dir)
{
  if (!domain) return NULL;
  /* A (re)binding may change where the catalog lives; drop any cached lookup. */
  forget_catalog (domain);
  for (Binding *b = bindings; b; b = b->next) {
    if (strcmp (b->domain, domain) == 0) {
      if (dir) { free (b->dir); b->dir = strdup (dir); }
      return b->dir;
    }
  }
  if (dir) {
    Binding *b = calloc (1, sizeof *b);
    b->domain = strdup (domain);
    b->dir = strdup (dir);
    b->next = bindings;
    bindings = b;
    return b->dir;
  }
  return NULL;
}

char *
g_libintl_bind_textdomain_codeset (const char *domain, const char *codeset)
{
  (void) domain;
  /* Catalogs are UTF-8 and GLib wants UTF-8; nothing to convert. */
  return (char *) codeset;
}
