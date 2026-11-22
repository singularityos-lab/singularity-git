project('singularity-git', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-git"', language: 'c')
subdir('po')

gnome = import('gnome')

gtk_dep       = dependency('gtk4')
gee_dep       = dependency('gee-0.8')
gtksource_dep = dependency('gtksourceview-5')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

subdir('ui')

resources = gnome.compile_resources(
  'singularity-git-resources',
  'resources/dev.sinty.git.gresource.xml',
  source_dir: [meson.current_source_dir(), meson.current_build_dir()],
  dependencies: main_ui
)

sources = files(
  'src/main.vala',
  'src/diff_window.vala',
  'src/window.vala',
  'src/app.vala',
  'src/agent_intents.vala',
)

executable('singularity-git',
  sources + [resources],
  dependencies: [gtk_dep, gee_dep, gtksource_dep, libsingularity_dep],
  install: true
)

shared_module('singularity-git-widget',
  files('widget/repo_status_widget.vala'),
  dependencies: [gtk_dep, gee_dep, libsingularity_dep, dependency('gio-unix-2.0')],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.git.repo-status.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

install_data('data/dev.sinty.git.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.git.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

iride = find_program('iride', required: get_option('iride'))
if iride.found()
  custom_target('iride-icon',
    input: 'data/icons/iride/iride.json',
    output: 'dev.sinty.git.iride',
    depend_files: files(
      'data/icons/iride/layers/000.svg',
      'data/icons/iride/layers/001.svg',
      'data/icons/iride/layers/002.svg',
      'data/icons/iride/layers/003.svg',
      'data/icons/iride/layers/004.svg',
      'data/icons/iride/layers/005.svg',
      'data/icons/iride/layers/006.svg',
      'data/icons/iride/layers/007.svg',
      'data/icons/iride/layers/008.svg',
      'data/icons/iride/layers/009.svg',
      'data/icons/iride/layers/010.svg',
      'data/icons/iride/layers/011.svg',
      'data/icons/iride/layers/012.svg',
      'data/icons/iride/layers/013.svg',
      'data/icons/iride/layers/014.svg',
      'data/icons/iride/layers/015.svg',
      'data/icons/iride/layers/016.svg',
      'data/icons/iride/layers/017.svg',
      'data/icons/iride/layers/018.svg',
      'data/icons/iride/layers/019.svg',
    ),
    command: [iride, 'build', meson.current_source_dir() / 'data' / 'icons' / 'iride', '@OUTPUT@'],
    install: true,
    install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
  )
endif

git_service_conf = configuration_data()
git_service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.git.service.in',
  output: 'dev.sinty.git.service',
  configuration: git_service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)
