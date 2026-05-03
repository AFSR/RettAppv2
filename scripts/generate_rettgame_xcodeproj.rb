#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Génère RettGame.xcodeproj — l'app standalone du jeu du regard.
# Usage : ruby scripts/generate_rettgame_xcodeproj.rb

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'RettGame.xcodeproj')
APP_DIR = 'RettGame'
APP_NAME = 'RettGame'
BUNDLE_ID = 'fr.afsr.RettGame'
DEPLOYMENT_TARGET = '17.0'
SWIFT_VERSION = '5.9'
MARKETING_VERSION = '1.0.0'
CURRENT_PROJECT_VERSION = '1'

# --- Cleanup --------------------------------------------------------------

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.development_region = 'fr'
project.root_object.known_regions = %w[fr Base en]

# --- Targets --------------------------------------------------------------

app_target = project.new_target(:application, APP_NAME, :ios, DEPLOYMENT_TARGET)

# --- Helpers --------------------------------------------------------------

def add_sources_recursively(group, disk_path, target)
  Dir.children(disk_path).sort.each do |entry|
    next if entry.start_with?('.')
    full = File.join(disk_path, entry)
    if File.directory?(full)
      next if entry.end_with?('.xcassets')
      sub = group.new_group(entry, entry)
      add_sources_recursively(sub, full, target)
    elsif entry.end_with?('.swift')
      file_ref = group.new_reference(entry)
      file_ref.last_known_file_type = 'sourcecode.swift'
      target.add_file_references([file_ref])
    end
  end
end

# --- Sources --------------------------------------------------------------

app_group = project.main_group.new_group(APP_NAME, APP_DIR)
app_group.source_tree = '<group>'
add_sources_recursively(app_group, File.join(ROOT, APP_DIR), app_target)

# --- Resources ------------------------------------------------------------

resources_group = app_group.groups.find { |g| g.name == 'Resources' }
assets_ref = resources_group.new_reference('Assets.xcassets')
assets_ref.last_known_file_type = 'folder.assetcatalog'
app_target.add_resources([assets_ref])
strings_ref = resources_group.new_reference('Localizable.strings')
strings_ref.last_known_file_type = 'text.plist.strings'
app_target.add_resources([strings_ref])
launch_ref = resources_group.new_reference('LaunchScreen.storyboard')
launch_ref.last_known_file_type = 'file.storyboard'
app_target.add_resources([launch_ref])
info_ref = resources_group.new_reference('Info.plist')
info_ref.last_known_file_type = 'text.plist.xml'
ent_ref = resources_group.new_reference("#{APP_NAME}.entitlements")
ent_ref.last_known_file_type = 'text.plist.entitlements'

# --- Build settings -------------------------------------------------------

common_settings = {
  'PRODUCT_BUNDLE_IDENTIFIER'            => BUNDLE_ID,
  'PRODUCT_NAME'                         => APP_NAME,
  'INFOPLIST_FILE'                       => "#{APP_DIR}/Resources/Info.plist",
  'CODE_SIGN_ENTITLEMENTS'               => "#{APP_DIR}/Resources/#{APP_NAME}.entitlements",
  'IPHONEOS_DEPLOYMENT_TARGET'           => DEPLOYMENT_TARGET,
  'SWIFT_VERSION'                        => SWIFT_VERSION,
  'TARGETED_DEVICE_FAMILY'               => '1,2',
  'MARKETING_VERSION'                    => MARKETING_VERSION,
  'CURRENT_PROJECT_VERSION'              => CURRENT_PROJECT_VERSION,
  'ENABLE_USER_SCRIPT_SANDBOXING'        => 'YES',
  'SWIFT_EMIT_LOC_STRINGS'               => 'YES',
  'SUPPORTS_MACCATALYST'                 => 'NO',
  'GENERATE_INFOPLIST_FILE'              => 'NO',
  'ASSETCATALOG_COMPILER_APPICON_NAME'   => 'AppIcon',
  'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad' =>
    'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone' =>
    'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
}

app_target.build_configurations.each do |config|
  config.build_settings.merge!(common_settings)
  if config.name == 'Debug'
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
  else
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
  end
end

project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  config.build_settings['SWIFT_VERSION'] = SWIFT_VERSION
  config.build_settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
  config.build_settings['ENABLE_BITCODE'] = 'NO'
end

project.save

# --- Shared scheme --------------------------------------------------------

scheme = Xcodeproj::XCScheme.new

build_action = Xcodeproj::XCScheme::BuildAction.new
app_entry = Xcodeproj::XCScheme::BuildAction::Entry.new(app_target)
app_entry.build_for_analyzing = true
app_entry.build_for_archiving = true
app_entry.build_for_profiling = true
app_entry.build_for_running = true
app_entry.build_for_testing = true
build_action.add_entry(app_entry)
scheme.build_action = build_action

launch_action = Xcodeproj::XCScheme::LaunchAction.new
launch_action.buildable_product_runnable =
  Xcodeproj::XCScheme::BuildableProductRunnable.new(app_target, 0)
scheme.launch_action = launch_action

profile_action = Xcodeproj::XCScheme::ProfileAction.new
profile_action.buildable_product_runnable =
  Xcodeproj::XCScheme::BuildableProductRunnable.new(app_target, 0)
scheme.profile_action = profile_action

scheme.save_as(PROJECT_PATH, APP_NAME, true)

puts "✅ #{PROJECT_PATH} généré"
puts "   Bundle ID : #{BUNDLE_ID}"
puts "   Version : #{MARKETING_VERSION} (#{CURRENT_PROJECT_VERSION})"
puts "   iOS #{DEPLOYMENT_TARGET}+ · Swift #{SWIFT_VERSION}"
puts
puts "Ouvre le projet : open RettGame.xcodeproj"
