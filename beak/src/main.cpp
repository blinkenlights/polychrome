#include "app.h"

int main(int ac, char *av[])
{
  auto app = MainApp();
  return app.findAndRunCommand(ac, av);
}
