import React, {useState, useRef, useEffect} from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  Image,
  NativeModules,
  NativeEventEmitter,
  Platform,
  ActivityIndicator,
} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {colors, typography, spacing, borderRadius} from '../../theme';
import {PoseResult} from '../../types';
import {
  getCurrentUser,
  saveMeasurement,
  uploadPhoto,
  calculateWeekPostOp,
} from '../../services/firebase';

const {CameraModule, PoseDetectionModule} = NativeModules;

type MeasurementType = 'extension' | 'flexion';
type ScreenState = 'camera' | 'result' | 'saving';

const MeasureScreen = () => {
  const [measurementType, setMeasurementType] =
    useState<MeasurementType>('extension');
  const [screenState, setScreenState] = useState<ScreenState>('camera');
  const [capturedPhoto, setCapturedPhoto] = useState<string | null>(null);
  const [poseResult, setPoseResult] = useState<PoseResult | null>(null);
  const [isCameraReady, setIsCameraReady] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Check camera permissions
    checkCameraPermission();
  }, []);

  const checkCameraPermission = async () => {
    try {
      if (CameraModule && CameraModule.requestPermission) {
        const granted = await CameraModule.requestPermission();
        if (!granted) {
          setIsCameraReady(false);
          setError('Camera permission is required to take measurements');
          return;
        }

        // Initialize camera after permission granted
        if (CameraModule.setupCamera) {
          await CameraModule.setupCamera();
        }
        setIsCameraReady(true);
      } else {
        // Native module not available, show placeholder
        setIsCameraReady(false);
        setError('Camera module not available. Build native modules first.');
      }
    } catch (err) {
      console.error('Camera permission error:', err);
      setError('Failed to access camera');
    }
  };

  const handleCapture = async () => {
    if (!CameraModule) {
      // Simulate capture for testing without native module
      simulateCapture();
      return;
    }

    setIsProcessing(true);
    try {
      // Capture photo
      const photoUri = await CameraModule.capturePhoto();
      setCapturedPhoto(photoUri);

      // Detect pose
      if (PoseDetectionModule) {
        const result = await PoseDetectionModule.detectPose(photoUri);
        setPoseResult(result);
      }

      setScreenState('result');
    } catch (err) {
      console.error('Capture error:', err);
      Alert.alert('Error', 'Failed to capture photo. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const simulateCapture = () => {
    // For testing without native modules
    setIsProcessing(true);
    setTimeout(() => {
      const simulatedAngle = measurementType === 'extension'
        ? Math.floor(Math.random() * 15) // 0-15 degrees for extension
        : 90 + Math.floor(Math.random() * 45); // 90-135 for flexion

      setPoseResult({
        hip: {x: 100, y: 100, confidence: 0.9},
        knee: {x: 150, y: 200, confidence: 0.9},
        ankle: {x: 200, y: 350, confidence: 0.9},
        angle: simulatedAngle,
      });
      setCapturedPhoto('simulated');
      setScreenState('result');
      setIsProcessing(false);
    }, 1000);
  };

  const handleSave = async () => {
    if (!poseResult) return;

    setScreenState('saving');
    try {
      const user = getCurrentUser();
      if (!user) {
        Alert.alert('Error', 'User not authenticated');
        return;
      }

      // Get surgery date to calculate week
      const surgeryDateStr = await AsyncStorage.getItem('surgeryDate');
      const surgeryDate = surgeryDateStr
        ? new Date(surgeryDateStr)
        : new Date();
      const weekPostOp = calculateWeekPostOp(surgeryDate);

      // Generate a unique ID for the measurement
      const measurementId = Date.now().toString();

      // Upload photo if available (skip for simulated)
      let photoUrl = '';
      if (capturedPhoto && capturedPhoto !== 'simulated') {
        photoUrl = await uploadPhoto(user.uid, measurementId, capturedPhoto);
      }

      // Save measurement
      await saveMeasurement(user.uid, {
        type: measurementType,
        angle: poseResult.angle,
        timestamp: new Date(),
        weekPostOp,
        photoUrl,
      });

      Alert.alert('Success', 'Measurement saved!', [
        {
          text: 'OK',
          onPress: handleRetake,
        },
      ]);
    } catch (err) {
      console.error('Save error:', err);
      Alert.alert('Error', 'Failed to save measurement. Please try again.');
      setScreenState('result');
    }
  };

  const handleRetake = () => {
    setCapturedPhoto(null);
    setPoseResult(null);
    setScreenState('camera');
  };

  if (screenState === 'result' || screenState === 'saving') {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.resultContainer}>
          <View style={styles.resultHeader}>
            <Text style={styles.resultTitle}>
              {measurementType === 'extension' ? 'Extension' : 'Flexion'} Result
            </Text>
          </View>

          <View style={styles.photoContainer}>
            {capturedPhoto && capturedPhoto !== 'simulated' ? (
              <Image
                source={{uri: capturedPhoto}}
                style={styles.capturedImage}
                resizeMode="contain"
              />
            ) : (
              <View style={styles.placeholderImage}>
                <Text style={styles.placeholderText}>Photo Preview</Text>
              </View>
            )}

            {/* Keypoint overlay would go here */}
          </View>

          <View style={styles.angleDisplay}>
            <Text style={styles.angleLabel}>Measured Angle</Text>
            <Text style={styles.angleValue}>{poseResult?.angle || '--'}°</Text>
            <Text style={styles.angleGoal}>
              Goal: {measurementType === 'extension' ? '0°' : '135°'}
            </Text>
          </View>

          <View style={styles.resultActions}>
            <TouchableOpacity
              style={styles.retakeButton}
              onPress={handleRetake}
              disabled={screenState === 'saving'}>
              <Text style={styles.retakeButtonText}>Retake</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[
                styles.saveButton,
                screenState === 'saving' && styles.buttonDisabled,
              ]}
              onPress={handleSave}
              disabled={screenState === 'saving'}>
              {screenState === 'saving' ? (
                <ActivityIndicator color={colors.text} />
              ) : (
                <Text style={styles.saveButtonText}>Save</Text>
              )}
            </TouchableOpacity>
          </View>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Measure</Text>
      </View>

      <View style={styles.typeToggle}>
        {(['extension', 'flexion'] as MeasurementType[]).map(type => (
          <TouchableOpacity
            key={type}
            style={[
              styles.typeButton,
              measurementType === type && styles.typeButtonActive,
            ]}
            onPress={() => setMeasurementType(type)}>
            <Text
              style={[
                styles.typeButtonText,
                measurementType === type && styles.typeButtonTextActive,
              ]}>
              {type === 'extension' ? 'Extension' : 'Flexion'}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      <View style={styles.cameraContainer}>
        {error ? (
          <View style={styles.cameraPlaceholder}>
            <Text style={styles.errorText}>{error}</Text>
            <TouchableOpacity
              style={styles.retryButton}
              onPress={checkCameraPermission}>
              <Text style={styles.retryButtonText}>Retry</Text>
            </TouchableOpacity>
          </View>
        ) : (
          <View style={styles.cameraPreview}>
            {/* Native camera view would be rendered here */}
            <View style={styles.cameraPlaceholder}>
              <Text style={styles.placeholderText}>Camera Preview</Text>
              <Text style={styles.placeholderSubtext}>
                Position your leg in frame
              </Text>
            </View>

            {/* Guide overlay */}
            <View style={styles.guideOverlay}>
              <View style={styles.guideLine} />
              <View
                style={[
                  styles.guideCircle,
                  {top: '30%'},
                ]}
              />
              <View
                style={[
                  styles.guideCircle,
                  {top: '50%'},
                ]}
              />
              <View
                style={[
                  styles.guideCircle,
                  {top: '70%'},
                ]}
              />
            </View>
          </View>
        )}
      </View>

      <View style={styles.instructions}>
        <Text style={styles.instructionText}>
          {measurementType === 'extension'
            ? 'Straighten your leg as much as possible and capture from the side'
            : 'Bend your knee as much as possible and capture from the side'}
        </Text>
      </View>

      <View style={styles.captureContainer}>
        <TouchableOpacity
          style={[
            styles.captureButton,
            isProcessing && styles.captureButtonDisabled,
          ]}
          onPress={handleCapture}
          disabled={isProcessing}
          activeOpacity={0.8}>
          {isProcessing ? (
            <ActivityIndicator color={colors.background} size="large" />
          ) : (
            <View style={styles.captureButtonInner} />
          )}
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  title: {
    ...typography.largeTitle,
    color: colors.text,
  },
  typeToggle: {
    flexDirection: 'row',
    marginHorizontal: spacing.lg,
    marginBottom: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.xs,
  },
  typeButton: {
    flex: 1,
    paddingVertical: spacing.sm,
    alignItems: 'center',
    borderRadius: borderRadius.md,
  },
  typeButtonActive: {
    backgroundColor: colors.primary,
  },
  typeButtonText: {
    ...typography.headline,
    color: colors.textSecondary,
  },
  typeButtonTextActive: {
    color: colors.text,
  },
  cameraContainer: {
    flex: 1,
    marginHorizontal: spacing.lg,
    borderRadius: borderRadius.lg,
    overflow: 'hidden',
    backgroundColor: colors.surface,
  },
  cameraPreview: {
    flex: 1,
    position: 'relative',
  },
  cameraPlaceholder: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.surface,
  },
  placeholderText: {
    ...typography.title3,
    color: colors.textSecondary,
    marginBottom: spacing.xs,
  },
  placeholderSubtext: {
    ...typography.body,
    color: colors.textTertiary,
  },
  errorText: {
    ...typography.body,
    color: colors.error,
    textAlign: 'center',
    marginBottom: spacing.md,
    paddingHorizontal: spacing.lg,
  },
  retryButton: {
    backgroundColor: colors.surfaceLight,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.lg,
    borderRadius: borderRadius.md,
  },
  retryButtonText: {
    ...typography.headline,
    color: colors.text,
  },
  guideOverlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
  },
  guideLine: {
    position: 'absolute',
    width: 2,
    height: '60%',
    backgroundColor: colors.primary + '40',
  },
  guideCircle: {
    position: 'absolute',
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    borderColor: colors.primary + '60',
    backgroundColor: 'transparent',
  },
  instructions: {
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
  },
  instructionText: {
    ...typography.subhead,
    color: colors.textSecondary,
    textAlign: 'center',
  },
  captureContainer: {
    alignItems: 'center',
    paddingBottom: spacing.xl,
  },
  captureButton: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 4,
    borderColor: colors.text,
  },
  captureButtonDisabled: {
    opacity: 0.7,
  },
  captureButtonInner: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: colors.primary,
  },
  // Result screen styles
  resultContainer: {
    flex: 1,
    padding: spacing.lg,
  },
  resultHeader: {
    marginBottom: spacing.md,
  },
  resultTitle: {
    ...typography.title2,
    color: colors.text,
  },
  photoContainer: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    overflow: 'hidden',
    marginBottom: spacing.lg,
  },
  capturedImage: {
    flex: 1,
  },
  placeholderImage: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  angleDisplay: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.xl,
    marginBottom: spacing.lg,
  },
  angleLabel: {
    ...typography.footnote,
    color: colors.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: spacing.xs,
  },
  angleValue: {
    fontSize: 64,
    fontWeight: '700',
    color: colors.text,
    lineHeight: 72,
  },
  angleGoal: {
    ...typography.body,
    color: colors.textTertiary,
    marginTop: spacing.xs,
  },
  resultActions: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  retakeButton: {
    flex: 1,
    backgroundColor: colors.surface,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    alignItems: 'center',
  },
  retakeButtonText: {
    ...typography.headline,
    color: colors.text,
  },
  saveButton: {
    flex: 1,
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    alignItems: 'center',
  },
  saveButtonText: {
    ...typography.headline,
    color: colors.text,
  },
  buttonDisabled: {
    opacity: 0.7,
  },
});

export default MeasureScreen;
