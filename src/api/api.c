#include "api.h"

int luaopen_system(lua_State *L);
int luaopen_renderer(lua_State *L);
int luaopen_renwindow(lua_State *L);
int luaopen_regex(lua_State *L);
int luaopen_process(lua_State *L);
int luaopen_thread(lua_State* L);
int luaopen_dirmonitor(lua_State* L);
int luaopen_shmem(lua_State* L);
int luaopen_utf8extra(lua_State* L);
int luaopen_encoding(lua_State* L);

#ifdef LUA_JIT
  int luaopen_compat53_string(lua_State *L);
  int luaopen_compat53_table(lua_State *L);
  int luaopen_compat53_utf8(lua_State *L);
  #define LUAJIT_COMPATIBILITY \
    { "compat53.string", luaopen_compat53_string }, \
    { "compat53.table", luaopen_compat53_table }, \
    { "compat53.utf8", luaopen_compat53_utf8 },
#else
  int luaopen_bit(lua_State *L);
  #define LUAJIT_COMPATIBILITY { "bit", luaopen_bit },
#endif

static const luaL_Reg libs[] = {
  { "system",     luaopen_system     },
  { "renderer",   luaopen_renderer   },
  { "renwindow",  luaopen_renwindow  },
  { "regex",      luaopen_regex      },
  { "process",    luaopen_process    },
  { "thread",     luaopen_thread     },
  { "dirmonitor", luaopen_dirmonitor },
  { "utf8extra",  luaopen_utf8extra  },
  { "encoding",   luaopen_encoding   },
  { "shmem",      luaopen_shmem      },
  LUAJIT_COMPATIBILITY
  { NULL, NULL }
};


void api_load_libs(lua_State *L) {
  for (int i = 0; libs[i].name; i++)
    luaL_requiref(L, libs[i].name, libs[i].func, 1);
}
