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
  'src/git_backend.vala',
  'src/diff_view.vala',
  'src/diff_window.vala',
  'src/window.vala',
  'src/app.vala',
)

executable('singularity-git',
  sources + [resources],
  dependencies: [gtk_dep, gee_dep, gtksource_dep, libsingularity_dep],
  install: true
)

install_data('data/dev.sinty.git.desktop',
  install_dir: get_option('datadir') / 'applications'
)
