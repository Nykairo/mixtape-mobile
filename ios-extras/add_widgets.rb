# Adds the home screen widgets to the iPhone project `flutter create` makes: a widget extension built
# from ios-extras/widgets, embedded in the app and sharing an App Group with it. The app gets the
# widgets' keys too (Intents.swift): an audio intent the app has runs inside the app, next to the music.
#
#   ruby ios-extras/add_widgets.rb     (after flutter create, from the project's folder or anywhere)

require 'fileutils'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
ios = File.join(root, 'ios')
version, build = File.read(File.join(root, 'pubspec.yaml'))[/^version:\s*(\S+)/, 1].split('+')

project = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
app = project.targets.find { |t| t.name == 'Runner' } or abort('no Runner target in the iPhone project')
if project.targets.any? { |t| t.name == 'MixtapeWidgets' }
  puts 'the widgets are in the project already'
  exit 0
end

# the widgets' files, the fonts they write with, and the App Group for the app
dir = File.join(ios, 'MixtapeWidgets')
FileUtils.mkdir_p(dir)
Dir[File.join(root, 'ios-extras', 'widgets', '*')].each { |f| FileUtils.cp(f, dir) }
%w[CoveredByYourGrace BarlowCondensed-Bold Barlow-SemiBold Barlow-Medium].each do |font|
  FileUtils.cp(File.join(root, 'assets', 'fonts', "#{font}.ttf"), dir)
end
FileUtils.cp(File.join(root, 'ios-extras', 'Runner.entitlements'), File.join(ios, 'Runner', 'Runner.entitlements'))

widgets = project.new_target(:app_extension, 'MixtapeWidgets', :ios, '14.0')
group = project.main_group.new_group('MixtapeWidgets', 'MixtapeWidgets')
swift = Dir[File.join(dir, '*.swift')].sort.map { |f| group.new_reference(File.basename(f)) }
fonts = Dir[File.join(dir, '*.ttf')].sort.map { |f| group.new_reference(File.basename(f)) }
group.new_reference('Info.plist')
group.new_reference('MixtapeWidgets.entitlements')
widgets.add_file_references(swift)
widgets.add_resources(fonts)

app.add_file_references(swift.select { |r| r.path == 'Intents.swift' })
project.main_group.groups.find { |g| g.display_name == 'Runner' }&.new_reference('Runner.entitlements')

widgets.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.softwarevault.mixtape.widgets'
  s['INFOPLIST_FILE'] = 'MixtapeWidgets/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'MixtapeWidgets/MixtapeWidgets.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['MARKETING_VERSION'] = version
  s['CURRENT_PROJECT_VERSION'] = build || '1'
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  # the keys need iOS 17; on older iPhones the widgets still show, without them
  s['OTHER_LDFLAGS'] = ['$(inherited)', '-weak_framework', 'AppIntents']
end

app.build_configurations.each do |c|
  s = c.build_settings
  s['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  flags = Array(s['OTHER_LDFLAGS'] || '$(inherited)')
  s['OTHER_LDFLAGS'] = flags + ['-weak_framework', 'AppIntents'] unless flags.include?('AppIntents')
end

# the extension goes inside the app, copied before Flutter's "Thin Binary" step (after it, Xcode sees
# a cycle and stops)
app.add_dependency(widgets)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widgets.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
thin = app.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  app.build_phases.delete(embed)
  app.build_phases.insert(thin, embed)
end

project.save
puts "the widgets are in the project: #{widgets.name}, #{version} (#{build || 1})"
