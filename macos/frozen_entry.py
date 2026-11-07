"""Desktop CLI entry point, including a radio-free packaging health check."""
import sys
from pathlib import Path

# Permit execution from source as well as the frozen distribution.
if not getattr(sys, 'frozen', False):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def packaging_smoke():
    import configparser
    import logging
    from types import SimpleNamespace

    import engineio.async_drivers.threading  # noqa: F401

    import modules
    import modules.core  # noqa: F401 -- verify transitive runtime dependencies
    import modules.web_viewer.app  # noqa: F401
    from modules.plugin_loader import PluginLoader

    root = Path(modules.__file__).resolve().parent
    loader = PluginLoader(SimpleNamespace(config=configparser.ConfigParser(), logger=logging.getLogger('smoke')))
    discovered = loader.discover_plugins()
    assert 'help_command' in discovered, f'Command sources missing: {discovered}'
    for name in discovered:
        __import__(f'modules.commands.{name}')
    assert (root / 'web_viewer/templates/base.html').is_file()
    assert (root / 'web_viewer/static/css/theme.css').is_file()
    assert (root.parent / 'translations').is_dir()
    assert (root.parent / 'data').is_dir()
    print(f'Packaging smoke passed: {len(discovered)} command modules, web viewer and assets')


if __name__ == '__main__':
    if sys.argv[1:] == ['--packaging-smoke']:
        packaging_smoke()
    elif '--desktop-viewer' in sys.argv[1:]:
        from modules.web_viewer.app import main as viewer_main

        sys.argv.remove('--desktop-viewer')
        viewer_main()
    else:
        from meshcore_bot import main
        main()
