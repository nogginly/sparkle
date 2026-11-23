#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include "ponyc.h"
#include "ast/ast.h"
#include "ast/source.h"
#include "ast/stringtab.h"
#include "ast/token.h"
#include "ast/error.h"
#include "pass/pass.h"
#include "pkg/package.h"

/* Options and error text that Crystal cannot reach without mirroring
 * pass_opt_t. */

pass_opt_t* spk_opt_new(const char* output, const char* bin_name,
  const char* search_paths)
{
  pass_opt_t* opt = malloc(sizeof(pass_opt_t));
  pass_opt_init(opt);
  opt->release = true;
  opt->verbosity = VERBOSITY_QUIET;
  opt->output = output;
  opt->bin_name = bin_name;
  opt->argv0 = "sparkle";
  module_add_paths(search_paths, opt);
  return opt;
}

#if defined(__linux__)
int GC_get_suspend_signal(void);
int GC_get_thr_restart_signal(void);
#endif

/* ponyc_init, keeping the garbage collector's thread-suspend signals.
 * LLVM's crash handlers, installed by ponyc_init, would otherwise intercept
 * them and print a bug-report banner before passing them on. */
bool spk_ponyc_init(pass_opt_t* opt)
{
#if defined(__linux__)
  int signals[2] = {GC_get_suspend_signal(), GC_get_thr_restart_signal()};
  struct sigaction saved[2];
  for(int i = 0; i < 2; i++)
    sigaction(signals[i], NULL, &saved[i]);
#endif
  bool ok = ponyc_init(opt);
#if defined(__linux__)
  for(int i = 0; i < 2; i++)
    sigaction(signals[i], &saved[i], NULL);
#endif
  return ok;
}

void spk_opt_free(pass_opt_t* opt)
{
  pass_opt_done(opt);
  free(opt);
}

const int spk_pass_expr = PASS_EXPR;

void spk_opt_set_limit(pass_opt_t* opt, int limit)
{
  opt->limit = (pass_id)limit;
}

errors_t* spk_opt_errors(pass_opt_t* opt)
{
  return opt->check.errors;
}

/* The collected errors, printed as ponyc prints them; free() the result. */
char* spk_errors_text(pass_opt_t* opt)
{
  char* text = NULL;
  size_t len = 0;
  FILE* fp = open_memstream(&text, &len);
  errors_set_output_stream(opt->check.errors, fp);
  errors_print(opt->check.errors);
  fclose(fp);
  return text;
}

const int spk_pass_parse = PASS_PARSE;
const int spk_pass_all = PASS_ALL;
const int spk_pass_finaliser = PASS_FINALISER;
const unsigned int spk_flag_preserve = AST_FLAG_PRESERVE;
const int spk_tk_actor = TK_ACTOR;
const int spk_tk_last = TK_TEST_EXTRA;

/* Drops the errors reported so far, so the next pass reports only its own. */
void spk_errors_reset(pass_opt_t* opt)
{
  errors_free(opt->check.errors);
  opt->check.errors = errors_alloc();
}

/* Loads the package at `path` into `program` parsed only, so that nodes can
 * be added to it before the passes run. module_load would otherwise bring a
 * late package straight up to the program's pass, while it is still empty. */
ast_t* spk_module_load_parsed(ast_t* program, const char* path, pass_opt_t* opt)
{
  pass_id caught_up = opt->program_pass;
  opt->program_pass = PASS_PARSE;
  ast_t* module = module_load(program, path, opt);
  opt->program_pass = caught_up;
  return module;
}

/* Runs the passes up to the options' limit over `program` again, as a build
 * does. Only the root's record of its last pass is cleared: packages that
 * have been through the passes keep theirs and are skipped, and a package
 * imported on the way catches up pass by pass, as in a build. */
bool spk_program_passes(ast_t* program, pass_opt_t* opt)
{
  ast_clearflag(program, AST_FLAG_PASS_MASK);
  opt->program_pass = PASS_PARSE;
  return ast_passes_program(program, opt);
}

strtable_t* spk_opt_strtab(pass_opt_t* opt)
{
  return opt->strtab;
}

/* A source named `file` holding `text`, for positions set with ast_setpos.
 * It lives until the process ends, because errors refer to it. */
source_t* spk_source_new(pass_opt_t* opt, const char* file, const char* text)
{
  source_t* source = source_open_string(text);
  source->file = stringtab(opt->strtab, file);
  return source;
}

/* `ast` printed as `ponyc --ast` prints it; free() the result. */
char* spk_ast_text(ast_t* ast)
{
  char* text = NULL;
  size_t len = 0;
  FILE* fp = open_memstream(&text, &len);
  ast_fprint(fp, ast, 80);
  fclose(fp);
  return text;
}
