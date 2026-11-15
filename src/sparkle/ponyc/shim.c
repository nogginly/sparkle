#include <stdio.h>
#include <stdlib.h>
#include "ponyc.h"
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
