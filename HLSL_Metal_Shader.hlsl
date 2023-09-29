Texture2D shaderTexture : register (t0);//Diffuse texure map
TextureCube gCubeMap : register (t16);//Environment reflection cube map (Use the .dds sample included)

SamplerState SampleType;
SamplerState SampleTypeCubeMap: register(s5);

//Material of the current object
cbuffer MaterialBuffer : register(b4)
{
	float4 CurAmbient;
	float4 CurTint;
	float4 CurSpecular;
	float4 CurReflect;
	float4 lightPosition;
};

struct Light
{
	float3 Strength;
	float FalloffStart; // point/spot light only
	float3 Direction;   // directional/spot light only
	float FalloffEnd;   // point/spot light only
	float3 Position;    // point light only
	float SpotPower;    // spot light only
};

struct Material
{
	float4 DiffuseAlbedo;
	float3 FresnelR0;
	float Shininess;
};

// Schlick gives an approximation to Fresnel reflectance (see pg. 233 "Real-Time Rendering 3rd Ed.").
// R0 = ( (n-1)/(n+1) )^2, where n is the index of refraction.
float3 SchlickFresnel(float3 R0, float3 normal, float3 lightVec)
{
	float cosIncidentAngle = saturate(dot(normal, lightVec));
	
	float f0 = 1.0f - cosIncidentAngle;
	float3 reflectPercent = R0 + (1.0f - R0)*(f0*f0*f0*f0*f0);
	
	return reflectPercent;
}

float3 BlinnPhong(float3 lightStrength, float3 lightVec, float3 normal, float3 toEye, Material mat)
{
	const float m = mat.Shininess * 256.0f;
	float3 halfVec = normalize(toEye + lightVec);
	
	float roughnessFactor = (m + 8.0f)*pow(max(dot(halfVec, normal), 0.0f), m) / 8.0f;
	float3 fresnelFactor = SchlickFresnel(mat.FresnelR0, halfVec, lightVec);
	
	float3 specAlbedo = fresnelFactor*roughnessFactor;
	
	//Our spec formula goes outside [0,1] range, but we are 
	//doing LDR rendering.  So scale it down a bit.
	specAlbedo = specAlbedo / (specAlbedo + 1.0f);
	
	return (mat.DiffuseAlbedo.rgb + specAlbedo) * lightStrength;
}


//Evaluates the lighting equation for directional lights.
float3 ComputeDirectionalLight_3(Light L, Material mat, float3 normal, float3 toEye, float3 position)
{
	float3 lightVec = lightPosition - position;
	
	//Scale light down by Lambert's cosine law.
	float ndotl = max(dot(lightVec, normal), 0.0f);
	float3 lightStrength = L.Strength * ndotl;
	
	return BlinnPhong(lightStrength, lightVec, normal, toEye, mat);
}

cbuffer MatrixBuffer : register(b7)
{
	matrix worldMatrix;
	matrix viewMatrix;
	matrix projectionMatrix;
};

cbuffer UniBuffer : register(b1)// From ::CameraMatrixBuffer in the cpp!
{
	float3 cameraPosition;
	float padding;
};

struct VertexIn
{
	float4 position : POSITION;
	float2 tex : TEXCOORD0;
	float3 normal : NORMAL;
	float4 color : COLOR0;
};

struct VertexOut
{
	float4 position : SV_POSITION;//Not used in the pixel shader!
	float3 PosW : POSITION;
	float3 normal : NORMAL;
	float2 tex : TEXCOORD1;
	float3 color : COLOR0;
	float3 cubeTexCoord : TEXCOORD2;
	
	float3 lightPos1 : TEXCOORD3;
	float3 lightPos2 : TEXCOORD4;
	float3 lightPos3 : TEXCOORD5;
	float3 lightPos4 : TEXCOORD6;
	
	float3 viewDirection : TEXCOORD7;
};


VertexOut VS(VertexIn vin)
{
	float4 worldPosition;
	
	VertexOut vout;
	
	vout.color = vin.color;
	
	//Change the position vector to be 4 units for proper matrix calculations.
	vin.position.w = 1.0f;
	
	//Calculate the position of the vertex against the world, view, and projection matrices.
	vout.position = mul(vin.position, worldMatrix);
	vout.position = mul(vout.position, viewMatrix);
	vout.position = mul(vout.position, projectionMatrix);
	
	vout.PosW = vin.position;
	
	//Store the texture coordinates for the pixel shader.
	vout.tex = vin.tex;
	
	//Calculate the normal vector against the world matrix only.
	vout.normal = mul(vin.normal, (float3x3)worldMatrix);
	vout.normal = vin.normal;
	
	vout.cubeTexCoord = vin.position;//Set cubemap texture coords
	
	//Light positions
	float3 lightPos1;
	lightPos1.x = -3.0;
	lightPos1.y = 1.0;
	lightPos1.z = 3.0;
	
	float3 lightPos2;
	lightPos2.x = 3.0;
	lightPos2.y = 1.0;
	lightPos2.z = 3.0;
	
	float3 lightPos3;
	lightPos3.x = -3.0;
	lightPos3.y = 1.0;
	lightPos3.z = -3.0;
	
	float3 lightPos4;
	lightPos4.x = 3.0;
	lightPos4.y = 1.0;
	lightPos4.z = -3.0;
	
	//Determine the light positions based on the position of the lights and the position of the vertex in the world.
	vout.lightPos1.xyz = lightPos1.xyz - vin.position.xyz;
	vout.lightPos2.xyz = lightPos2.xyz - vin.position.xyz;
	vout.lightPos3.xyz = lightPos3.xyz - vin.position.xyz;
	vout.lightPos4.xyz = lightPos4.xyz - vin.position.xyz;
	
	//Normalize the light position vectors.
	vout.lightPos1 = normalize(vout.lightPos1);
	vout.lightPos2 = normalize(vout.lightPos2);
	vout.lightPos3 = normalize(vout.lightPos3);
	vout.lightPos4 = normalize(vout.lightPos4);
	
	//Compute view direction for specularity
	worldPosition = mul(vin.position, worldMatrix);
	vout.viewDirection = cameraPosition - worldPosition;
	vout.viewDirection = normalize(vout.viewDirection);
	
	return vout;
}

//NB: DX11 luna
struct DirectionalLight
{
	float4 Ambient;
	float4 Diffuse;
	float4 Specular;
	float3 Direction;
	float pad;
};

SamplerState samAnisotropic
{
	Filter = ANISOTROPIC;
	MaxAnisotropy = 4;
	AddressU = WRAP;
	AddressV = WRAP;
	AddressW = WRAP;
};

float4 PS(VertexOut pin) : SV_Target
{
	half4 rimColor;
	
	float4 textureDiffuse = shaderTexture.Sample(SampleType, pin.tex);//Texture mapped pixel
	
	//Interpolating normal can unnormalize it, so renormalize it.
	pin.normal = normalize(pin.normal);
	//Vector from point being lit to eye.
	float3 toEyeW = normalize(cameraPosition - pin.PosW);
	
	//-----Cube map reflection-----
	float3 cubeMapReflectionColor;
	float3 incident = -toEyeW;
	float3 reflectionVector = reflect(incident, pin.normal);
	float4 reflectionColor = gCubeMap.Sample(samAnisotropic, reflectionVector);//NB: Shader variable is: cubemap type
	cubeMapReflectionColor = reflectionColor;
	//-----------------------
	
	//[LIGHTS]
	float3 result = 0.0f;
	
	Material sMat;
	sMat.DiffuseAlbedo.x = textureDiffuse.x;//NB: Skull mat albdeo is: 1.0/1.0/1.0 in Luna engine
	sMat.DiffuseAlbedo.y = textureDiffuse.y;
	sMat.DiffuseAlbedo.z = textureDiffuse.z;
	sMat.FresnelR0.x = 0.05;
	sMat.FresnelR0.y = 0.05;
	sMat.FresnelR0.z = 0.05;
	sMat.Shininess = CurSpecular;
	
	float reflectAmount = 0.3;// or use: CurReflect;
	
	//[Merge the cube map reflection with the texture diffuse based on CurReflect cBuffer input]
	float3 blendedColor;
	blendedColor = lerp(textureDiffuse, cubeMapReflectionColor, reflectAmount);
	
	sMat.DiffuseAlbedo.x = blendedColor.x;
	sMat.DiffuseAlbedo.y = blendedColor.y;
	sMat.DiffuseAlbedo.z = blendedColor.z;
	//-------------------------------------------
	
	float3 spotPos;
	spotPos.x = 1.0;
	spotPos.y = 0.0;
	spotPos.z = 0.4;
	
	float3 ambient3 = 0.3 * sMat.DiffuseAlbedo;
	
	Light spotLight_l;
	spotLight_l.Strength = 0.1;
	spotLight_l.FalloffEnd = 10.0;
	spotLight_l.FalloffStart = 1.0;
	spotLight_l.Direction.x = 0.57735;
	spotLight_l.Direction.y = -0.57735;
	spotLight_l.Direction.z = 0.57735;
	spotLight_l.Position.x = 0.0;
	spotLight_l.Position.y = 0.0;
	spotLight_l.Position.z = 0.0;
	spotLight_l.SpotPower = 64.0; 
	
	float shadowFactor = 1.0;
	result += clamp(CurAmbient + (shadowFactor * ComputeDirectionalLight_3(spotLight_l, sMat, pin.normal, toEyeW, pin.PosW)), 0.0, 1.0);
	
	float3 litColor3 = ambient3 + result;
	
	litColor3.x += CurTint.x;
	litColor3.y += CurTint.y;
	litColor3.z += CurTint.z;
	
	return float4(litColor3, 1.0f);
}
