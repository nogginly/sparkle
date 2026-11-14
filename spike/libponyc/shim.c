#include <stdlib.h>
#include "ponyc.h"
#include "ast/ast.h"
#include "ast/token.h"
#include "pass/pass.h"

/* Option fields that Crystal cannot reach without mirroring pass_opt_t. */

pass_opt_t* spk_opt_new(const char* output, const char* bin_name)
{
  pass_opt_t* opt = malloc(sizeof(pass_opt_t));
  pass_opt_init(opt);
  opt->release = true;
  opt->output = output;
  opt->bin_name = bin_name;
  opt->argv0 = "sparkle";
  return opt;
}

void spk_opt_free(pass_opt_t* opt)
{
  pass_opt_done(opt);
  free(opt);
}

void spk_opt_set_limit(pass_opt_t* opt, int limit) { opt->limit = (pass_id)limit; }
errors_t* spk_opt_errors(pass_opt_t* opt) { return opt->check.errors; }
strtable_t* spk_opt_strtab(pass_opt_t* opt) { return opt->strtab; }

/* Values from C enums. */

const int spk_pass_parse = PASS_PARSE;
const int spk_pass_all = PASS_ALL;
const int spk_tk_none = TK_NONE;
const int spk_tk_actor = TK_ACTOR;
const int spk_tk_members = TK_MEMBERS;
const int spk_tk_new = TK_NEW;
const int spk_tk_id = TK_ID;
const int spk_tk_params = TK_PARAMS;
const int spk_tk_param = TK_PARAM;
const int spk_tk_nominal = TK_NOMINAL;
const int spk_tk_seq = TK_SEQ;
const int spk_tk_call = TK_CALL;
const int spk_tk_dot = TK_DOT;
const int spk_tk_reference = TK_REFERENCE;
const int spk_tk_positionalargs = TK_POSITIONALARGS;
const int spk_tk_string = TK_STRING;
const int spk_tk_module = TK_MODULE;
const int spk_tk_file = TK_FILE;
