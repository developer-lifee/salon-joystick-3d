require "xcodeproj"

root = File.expand_path(File.dirname(__FILE__))
project_path = File.join(root, "SalonJoystick3D.xcodeproj")
project = Xcodeproj::Project.new(project_path)

app_target = project.new_target(:application, "SalonJoystick3D", :ios, "18.0")
app_target.add_system_framework("SceneKit")
app_target.add_system_framework("SwiftUI")
app_target.build_configurations.each do |config|
  config.build_settings["DEVELOPMENT_TEAM"] = ""
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.codex.salonjoystick3d"
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "18.0"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] = "YES"
  config.build_settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  config.build_settings["SWIFT_VERSION"] = "5.0"
end

group = project.main_group.new_group("Sources/SalonJoystick3D")
Dir[File.join(root, "Sources/SalonJoystick3D/*.swift")].sort.each do |file|
  group.new_file(file)
end
app_target.add_file_references(group.files)

project.save
