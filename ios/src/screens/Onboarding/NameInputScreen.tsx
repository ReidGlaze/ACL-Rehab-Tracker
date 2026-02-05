import React, {useState} from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {StackNavigationProp} from '@react-navigation/stack';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {colors, typography, spacing, borderRadius} from '../../theme';
import {RootStackParamList} from '../../types';

type NameInputScreenNavigationProp = StackNavigationProp<
  RootStackParamList,
  'NameInput'
>;

const NameInputScreen = () => {
  const navigation = useNavigation<NameInputScreenNavigationProp>();
  const [name, setName] = useState('');

  const handleContinue = async () => {
    if (name.trim()) {
      // Save name temporarily, will be saved to Firestore after surgery date
      await AsyncStorage.setItem('tempUserName', name.trim());
      navigation.navigate('SurgeryDate');
    }
  };

  const isValid = name.trim().length > 0;

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        style={styles.keyboardView}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        <View style={styles.content}>
          <View style={styles.headerSection}>
            <Text style={styles.title}>First Things First</Text>
            <Text style={styles.subtitle}>Your name</Text>
          </View>

          <View style={styles.inputSection}>
            <TextInput
              style={styles.input}
              placeholder="Name"
              placeholderTextColor={colors.textTertiary}
              value={name}
              onChangeText={setName}
              autoCapitalize="words"
              autoCorrect={false}
              autoFocus
            />
            <View style={styles.inputUnderline} />
          </View>
        </View>

        <View style={styles.footer}>
          <TouchableOpacity
            style={[styles.button, !isValid && styles.buttonDisabled]}
            onPress={handleContinue}
            disabled={!isValid}
            activeOpacity={0.8}>
            <Text style={styles.buttonArrow}>→</Text>
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  keyboardView: {
    flex: 1,
  },
  content: {
    flex: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.xxl,
  },
  headerSection: {
    marginBottom: spacing.xxl,
  },
  title: {
    ...typography.largeTitle,
    color: colors.text,
    marginBottom: spacing.xs,
  },
  subtitle: {
    ...typography.body,
    color: colors.textSecondary,
  },
  inputSection: {
    marginTop: spacing.xl,
  },
  input: {
    ...typography.largeTitle,
    color: colors.text,
    paddingVertical: spacing.md,
  },
  inputUnderline: {
    height: 2,
    backgroundColor: colors.primary,
  },
  footer: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xl,
  },
  button: {
    backgroundColor: colors.surfaceLight,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonArrow: {
    fontSize: 24,
    color: colors.text,
  },
});

export default NameInputScreen;
