@echo off
echo Deploying graph-tool Lambda...

cd lambda\graph-tool

REM Create package directory
if exist .package rmdir /s /q .package
mkdir .package

REM Install dependencies
pip install boto3 -t .package --quiet

REM Copy files
copy lambda_function.py .package\
if exist ..\common\logger.py copy ..\common\logger.py .package\

REM Create ZIP
if exist function.zip del function.zip
powershell Compress-Archive -Path .package\* -DestinationPath function.zip -Force

REM Clean up
rmdir /s /q .package

REM Upload to Lambda
"C:\Program Files\Amazon\AWSCLIV2\aws.exe" lambda update-function-code --function-name cc-graph-tool-dev --zip-file fileb://function.zip --region us-east-1

cd ..\..

echo.
echo Deployment complete!
echo.
echo Test with:
echo   aws lambda invoke --function-name cc-graph-tool-dev --payload file://test-payload.json response.json
pause
