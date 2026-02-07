#include "compiler_internal.h"
#include "utils/json.h"

const char *ios_sysroot(void)
{
#if __APPLE__
		static const char *xcode_ios_sysroot = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk";
		static const char *xcode_sim_sysroot = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk";
		if (file_is_dir(xcode_ios_sysroot)) return xcode_ios_sysroot;
		if (file_is_dir(xcode_sim_sysroot)) return xcode_sim_sysroot;
#endif
	return NULL;
}

static void parse_version(const char *version_string, Version *version)
{
	StringSlice slice = slice_from_string(version_string);
	StringSlice first = slice_next_token(&slice, '.');
	version->major = atoi(first.ptr);
	version->minor = atoi(slice.ptr);
}

iosSDK *ios_sysroot_sdk_information(const char *sdk_path)
{
	JsonParser parser;
	size_t len;

	scratch_buffer_clear();
	scratch_buffer_printf("%s/SDKSettings.json", sdk_path);
	const char *settings_json_path = scratch_buffer_to_string();
	if (!file_exists(settings_json_path)) error_exit("Invalid iOS SDK path: '%s'.", sdk_path);
	const char *file = file_read_all(settings_json_path, &len);
	json_init_string(&parser, file);
	iosSDK *sdk = CALLOCS(iosSDK);
	JSONObject *top_object = json_parse(&parser);
	JSONObject *supported_targets = json_map_get(top_object, "SupportedTargets");
	JSONObject *ios_target = json_map_get(supported_targets, "iphoneos");

	const char *default_deploy_target = json_map_get(ios_target, "DefaultDeploymentTarget")->str;
	parse_version(default_deploy_target, &sdk->ios_deploy_target);

	const char *min_deploy_target = json_map_get(ios_target, "MinimumDeploymentTarget")->str;
	parse_version(min_deploy_target, &sdk->ios_min_deploy_target);

	return sdk;
}