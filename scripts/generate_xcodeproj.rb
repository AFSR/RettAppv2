#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Génère RettApp.xcodeproj à partir de la structure de fichiers.
# Équivalent à `xcodegen generate` mais fonctionne sans macOS (utilise la gem xcodeproj).
#
# Usage : ruby scripts/generate_xcodeproj.rb

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'RettApp.xcodeproj')
APP_DIR = 'RettApp'
TESTS_DIR = 'RettAppTests'
APP_NAME = 'RettApp'
TESTS_NAME = 'RettAppTests'
BUNDLE_ID = 'fr.afsr.RettApp'
DEPLOYMENT_TARGET = '17.0'
SWIFT_VERSION = '5.9'

# --- Nettoyage --------------------------------------------------------------

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.development_region = 'fr'
project.root_object.known_regions = %w[fr Base en]

# --- Targets ----------------------------------------------------------------

app_target = project.new_target(:application, APP_NAME, :ios, DEPLOYMENT_TARGET)
test_target = project.new_target(:unit_test_bundle, TESTS_NAME, :ios, DEPLOYMENT_TARGET)

# --- Helpers ----------------------------------------------------------------

def add_sources_recursively(group, disk_path, target, project_root)
  Dir.children(disk_path).sort.each do |entry|
    next if entry.start_with?('.')
    full = File.join(disk_path, entry)
    if File.directory?(full)
      next if entry.end_with?('.xcassets') # géré séparément comme resource
      sub = group.new_group(entry, entry)
      add_sources_recursively(sub, full, target, project_root)
    elsif entry.end_with?('.swift')
      file_ref = group.new_reference(entry)
      file_ref.last_known_file_type = 'sourcecode.swift'
      target.add_file_references([file_ref])
    end
  end
end

def add_group_for_path(project, name, disk_path)
  group = project.main_group.new_group(name, disk_path)
  group.source_tree = '<group>'
  group
end

# --- App sources ------------------------------------------------------------

app_group = add_group_for_path(project, APP_NAME, APP_DIR)
add_sources_recursively(app_group, File.join(ROOT, APP_DIR), app_target, ROOT)

# --- App resources (Assets, Localizable) -----------------------------------

resources_group = app_group.groups.find { |g| g.name == 'Resources' }
# Assets.xcassets
assets_ref = resources_group.new_reference('Assets.xcassets')
assets_ref.last_known_file_type = 'folder.assetcatalog'
app_target.add_resources([assets_ref])
# Localizable.strings
strings_ref = resources_group.new_reference('Localizable.strings')
strings_ref.last_known_file_type = 'text.plist.strings'
app_target.add_resources([strings_ref])

# --- Tests sources ----------------------------------------------------------

tests_group = add_group_for_path(project, TESTS_NAME, TESTS_DIR)
add_sources_recursively(tests_group, File.join(ROOT, TESTS_DIR), test_target, ROOT)

# --- Build settings ---------------------------------------------------------

common_app_settings = {
  'PRODUCT_BUNDLE_IDENTIFIER'            => BUNDLE_ID,
  'PRODUCT_NAME'                         => APP_NAME,
  'INFOPLIST_FILE'                       => "#{APP_DIR}/Resources/Info.plist",
  'CODE_SIGN_ENTITLEMENTS'               => "#{APP_DIR}/Resources/#{APP_NAME}.entitlements",
  'IPHONEOS_DEPLOYMENT_TARGET'           => DEPLOYMENT_TARGET,
  'SWIFT_VERSION'                        => SWIFT_VERSION,
  'TARGETED_DEVICE_FAMILY'               => '1,2',
  'MARKETING_VERSION'                    => '1.0',
  'CURRENT_PROJECT_VERSION'              => '1',
  'ENABLE_USER_SCRIPT_SANDBOXING'        => 'YES',
  'SWIFT_EMIT_LOC_STRINGS'               => 'YES',
  'SUPPORTS_MACCATALYST'                 => 'NO',
  'GENERATE_INFOPLIST_FILE'              => 'NO',
  'DEVELOPMENT_ASSET_PATHS'              => '',
  'ASSETCATALOG_COMPILER_APPICON_NAME'   => 'AppIcon',
  'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
  'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad' =>
    'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone' =>
    'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
}

app_target.build_configurations.each do |config|
  config.build_settings.merge!(common_app_settings)
  if config.name == 'Debug'
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
  else
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
  end
end

common_test_settings = {
  'PRODUCT_BUNDLE_IDENTIFIER'   => "#{BUNDLE_ID}.tests",
  'PRODUCT_NAME'                => TESTS_NAME,
  'IPHONEOS_DEPLOYMENT_TARGET'  => DEPLOYMENT_TARGET,
  'SWIFT_VERSION'               => SWIFT_VERSION,
  'BUNDLE_LOADER'               => '$(TEST_HOST)',
  'TEST_HOST'                   => "$(BUILT_PRODUCTS_DIR)/#{APP_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/#{APP_NAME}",
  'GENERATE_INFOPLIST_FILE'     => 'YES'
}

test_target.build_configurations.each do |config|
  config.build_settings.merge!(common_test_settings)
end

# Dépendance tests → app
test_target.add_dependency(app_target)

# --- Project-level settings -------------------------------------------------

project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  config.build_settings['SWIFT_VERSION'] = SWIFT_VERSION
  config.build_settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
  config.build_settings['ENABLE_BITCODE'] = 'NO'
end

# --- Save -------------------------------------------------------------------

project.save

# --- Shared scheme ----------------------------------------------------------

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target)
# Les tests doivent être exécutables
test_action = scheme.test_action
test_ref = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
test_action.add_testable(test_ref)
scheme.save_as(PROJECT_PATH, APP_NAME, true)

puts "✅ #{PROJECT_PATH} généré"
puts "   Target app : #{APP_NAME} (#{BUNDLE_ID})"
puts "   Target tests : #{TESTS_NAME}"
puts "   iOS #{DEPLOYMENT_TARGET}+ · Swift #{SWIFT_VERSION}"
puts
puts "Ouvre le projet avec : open RettApp.xcodeproj"
