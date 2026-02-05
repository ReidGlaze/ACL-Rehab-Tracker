import React, {useState} from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Platform,
} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import DateTimePicker from '@react-native-community/datetimepicker';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {useNavigation} from '@react-navigation/native';
import {StackNavigationProp} from '@react-navigation/stack';
import {colors, typography, spacing, borderRadius} from '../../theme';
import {RootStackParamList} from '../../types';
import {
  getCurrentUser,
  saveUserProfile,
  calculateWeekPostOp,
} from '../../services/firebase';

type SurgeryDateScreenNavigationProp = StackNavigationProp<
  RootStackParamList,
  'SurgeryDate'
>;

interface SurgeryDateScreenProps {
  onComplete?: () => void;
}

const SurgeryDateScreen = ({onComplete}: SurgeryDateScreenProps) => {
  const navigation = useNavigation<SurgeryDateScreenNavigationProp>();
  const [date, setDate] = useState(new Date());
  const [showPicker, setShowPicker] = useState(Platform.OS === 'ios');
  const [isLoading, setIsLoading] = useState(false);

  const handleDateChange = (event: any, selectedDate?: Date) => {
    if (Platform.OS === 'android') {
      setShowPicker(false);
    }
    if (selectedDate) {
      setDate(selectedDate);
    }
  };

  const handleComplete = async () => {
    setIsLoading(true);
    try {
      const userName = await AsyncStorage.getItem('tempUserName');
      const user = getCurrentUser();

      if (user && userName) {
        // Save profile to Firestore
        await saveUserProfile(user.uid, {
          name: userName,
          surgeryDate: date,
          createdAt: new Date(),
        });

        // Mark onboarding as complete
        await AsyncStorage.setItem('onboardingComplete', 'true');
        await AsyncStorage.setItem('surgeryDate', date.toISOString());

        // Trigger navigation callback
        if (onComplete) {
          onComplete();
        }
      }
    } catch (error) {
      console.error('Error completing onboarding:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const weekPostOp = calculateWeekPostOp(date);
  const formattedDate = date.toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <View style={styles.headerSection}>
          <Text style={styles.title}>When was your{'\n'}surgery?</Text>
          <Text style={styles.subtitle}>
            This helps us calculate your recovery timeline
          </Text>
        </View>

        <View style={styles.dateSection}>
          {Platform.OS === 'android' && (
            <TouchableOpacity
              style={styles.dateButton}
              onPress={() => setShowPicker(true)}>
              <Text style={styles.dateButtonText}>{formattedDate}</Text>
            </TouchableOpacity>
          )}

          {showPicker && (
            <DateTimePicker
              value={date}
              mode="date"
              display={Platform.OS === 'ios' ? 'spinner' : 'default'}
              onChange={handleDateChange}
              maximumDate={new Date()}
              minimumDate={new Date(2020, 0, 1)}
              textColor={colors.text}
              themeVariant="dark"
              style={styles.datePicker}
            />
          )}
        </View>

        <View style={styles.weekInfo}>
          <Text style={styles.weekLabel}>You are currently in</Text>
          <Text style={styles.weekNumber}>Week {weekPostOp}</Text>
          <Text style={styles.weekSubtext}>of your recovery</Text>
        </View>
      </View>

      <View style={styles.footer}>
        <TouchableOpacity
          style={[styles.button, isLoading && styles.buttonDisabled]}
          onPress={handleComplete}
          disabled={isLoading}
          activeOpacity={0.8}>
          <Text style={styles.buttonText}>
            {isLoading ? 'Saving...' : 'Start Tracking'}
          </Text>
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
  content: {
    flex: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.xxl,
  },
  headerSection: {
    marginBottom: spacing.xl,
  },
  title: {
    ...typography.largeTitle,
    color: colors.text,
    marginBottom: spacing.sm,
  },
  subtitle: {
    ...typography.body,
    color: colors.textSecondary,
  },
  dateSection: {
    marginTop: spacing.xl,
    alignItems: 'center',
  },
  dateButton: {
    backgroundColor: colors.surface,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    borderRadius: borderRadius.md,
  },
  dateButtonText: {
    ...typography.headline,
    color: colors.text,
  },
  datePicker: {
    width: '100%',
    height: 200,
  },
  weekInfo: {
    marginTop: spacing.xxl,
    alignItems: 'center',
    backgroundColor: colors.surface,
    padding: spacing.xl,
    borderRadius: borderRadius.lg,
  },
  weekLabel: {
    ...typography.body,
    color: colors.textSecondary,
    marginBottom: spacing.xs,
  },
  weekNumber: {
    fontSize: 48,
    fontWeight: '700',
    color: colors.success,
    marginBottom: spacing.xs,
  },
  weekSubtext: {
    ...typography.body,
    color: colors.textSecondary,
  },
  footer: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xl,
  },
  button: {
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.7,
  },
  buttonText: {
    ...typography.headline,
    color: colors.text,
  },
});

export default SurgeryDateScreen;
